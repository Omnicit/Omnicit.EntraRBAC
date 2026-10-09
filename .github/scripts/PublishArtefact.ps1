#Requires -Version 7.2

<#
    .SYNOPSIS
        Records the module build that the test matrix proved, verifies a downloaded copy of it file
        by file, and proves that the package the Gallery serves is that build before it is tagged.

    .DESCRIPTION
        The publish job must ship the bytes the three required checks tested, and nothing else.
        Both halves of that proof live in this one file so they cannot drift apart: a recorder and
        a verifier that enumerated or hashed differently would fail on honest artefacts and agree
        on tampered ones.

        -Record runs on the ubuntu-latest leg of build-and-test, after its Test step. It writes
        publish-meta.json beside the built module, holding the commit, the version GitVersion
        computed, the version and prerelease the built manifest actually carries, and a SHA-256 for
        every file in the version folder.

        -Verify runs in the package job and again in the publish job, after the artefact is
        downloaded. It recomputes all of it, throws on the first disagreement, and returns the full
        path of the version folder it proved. That path is the one Publish-PSResource is given.

        -Compare runs in the publish job's tag step, on every run but a v-tag run. It does
        everything -Verify does, then reads the package the repository serves under the recorded
        version back with Save-PSResource, the way a consumer gets it, and compares it with the
        verified artefact file by file and SHA-256 by SHA-256, in both directions. It returns
        nothing when they are the same build. It throws when they differ, and when the package
        cannot be read, so the tag step never tags a commit whose tested build is not the published
        package. That is not hypothetical: when the tag step fails after a publish, no tag moves
        GitVersion's base, the next merge to main computes the same version, finds it published and
        skips the publish, and the tag step then tagged THAT merge's commit with the previous
        commit's package. See docs/development/rationale.md#publish-on-merge.

        -Path is, in every mode, the directory that CONTAINS module/<name>/<version>. That is
        output/ in the build job and the download directory downstream, because
        actions/upload-artifact roots an artefact at the least common ancestor of the paths it is
        given -- output/ for the module folder plus publish-meta.json. Keeping those two shapes
        equal is what lets one script read both.

        WHICH VERSION IS PUBLISHED. Publish-PSResource publishes the version in the MANIFEST, not
        the NuGetVersionV2 GitVersion computed, and the two are not always the same string. A
        PowerShell prerelease label must be alphanumeric, so Sampler keeps only the first
        hyphen-delimited segment of it: measured on 2026-09-22, GitVersion computed
        1.0.1-ci-publish-on-me0001 on a branch named ci/publish-on-merge while the manifest was
        stamped 1.0.1 with prerelease 'ci'. On main and on a v tag the two agree exactly
        (1.0.1-preview0001 stamps 1.0.1 plus 'preview0001', measured the same day). The downstream
        jobs therefore take the version to publish, to confirm and to tag from the MANIFEST, and
        this script asserts only what holds everywhere: that the manifest's ModuleVersion is the
        numeric part of NuGetVersionV2.

    .PARAMETER Record
        Write publish-meta.json for the build under -Path.

    .PARAMETER Verify
        Verify the build under -Path against the publish-meta.json sitting beside it.

    .PARAMETER Path
        The directory that contains module/<name>/<version>, and, in -Verify mode, publish-meta.json.

    .PARAMETER Sha
        The commit the build came from. Recorded in -Record mode; required to match in -Verify mode.

    .PARAMETER ModuleVersion
        NuGetVersionV2 as GitVersion computed it and the build job exported it. -Record only.

    .PARAMETER Compare
        Verify the build under -Path as -Verify does, then compare it with the package
        -Repository serves under the recorded version. Throws unless they are the same build.

    .PARAMETER Repository
        The repository to read the published package back from, as Save-PSResource names it.
        -Compare only.

    .PARAMETER DownloadPath
        An absolute path to an empty or missing directory. The published package is saved
        under it as module/<name>/<version>, the shape -Path has. -Compare only.

    .EXAMPLE
        ./.github/scripts/PublishArtefact.ps1 -Record -Path 'output' -Sha $env:GITHUB_SHA -ModuleVersion $env:ModuleVersion

    .EXAMPLE
        $ModulePath = ./.github/scripts/PublishArtefact.ps1 -Verify -Path 'artefact' -Sha $env:GITHUB_SHA

    .EXAMPLE
        ./.github/scripts/PublishArtefact.ps1 -Compare -Path 'artefact' -Sha $env:GITHUB_SHA -Repository 'PSGallery' -DownloadPath (Join-Path $env:RUNNER_TEMP 'published-package')
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Write-Host goes to the information stream, so the workflow log gets the narration while the version folder path stays this script''s only PIPELINE output -- which is what lets a caller write $ModulePath = ./PublishArtefact.ps1 -Verify. Write-Output would hand the caller the narration as well.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Verify',
    Justification = 'Switch is a parameter-set discriminator; the script branches on $Record and $Compare, and -Verify selects the remaining set.')]
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true, ParameterSetName = 'Record')]
    [switch]
    $Record,

    [Parameter(Mandatory = $true, ParameterSetName = 'Verify')]
    [switch]
    $Verify,

    [Parameter(Mandatory = $true, ParameterSetName = 'Compare')]
    [switch]
    $Compare,

    [Parameter(Mandatory = $true)]
    [string]
    $Path,

    [Parameter(Mandatory = $true)]
    [string]
    $Sha,

    [Parameter(Mandatory = $true, ParameterSetName = 'Record')]
    [string]
    $ModuleVersion,

    [Parameter(Mandatory = $true, ParameterSetName = 'Compare')]
    [string]
    $Repository,

    [Parameter(Mandatory = $true, ParameterSetName = 'Compare')]
    [string]
    $DownloadPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$ModuleName = 'Omnicit.EntraRBAC'
$MetaFileName = 'publish-meta.json'

function Get-VersionFolder
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Root
    )

    $ModuleRoot = Join-Path -Path $Root -ChildPath 'module' | Join-Path -ChildPath $ModuleName

    if (-not (Test-Path -LiteralPath $ModuleRoot))
    {
        throw ("No module folder at '{0}'. Either nothing was built, or -Path does not point at the directory that CONTAINS module/{1}." -f $ModuleRoot, $ModuleName)
    }

    <#
        Exactly one, never 'the first one'. A publish names one build; it does not choose between
        several, and a second folder here means the state is not one this script can prove.
    #>
    $Candidates = @(Get-ChildItem -LiteralPath $ModuleRoot -Directory)

    if ($Candidates.Count -ne 1)
    {
        throw ("Expected exactly one version folder under '{0}', found {1}: {2}." -f $ModuleRoot, $Candidates.Count, (($Candidates.Name | Sort-Object) -join ', '))
    }

    $Candidates[0]
}

function Get-ArtefactFileHash
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $VersionFolder
    )

    <#
        Paths are recorded RELATIVE to the version folder and with forward slashes, so the record a
        Linux runner writes is the record a Linux runner reads, and neither carries a
        runner-specific absolute prefix that would make every comparison fail for the wrong reason.
    #>
    $Prefix = (Resolve-Path -LiteralPath $VersionFolder).Path.TrimEnd('/', '\')

    Get-ChildItem -LiteralPath $VersionFolder -Recurse -File |
        ForEach-Object -Process {
            [PSCustomObject]@{
                Path   = $_.FullName.Substring($Prefix.Length + 1) -replace '\\', '/'
                Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        } |
        Sort-Object -Property 'Path'
}

function Get-ManifestFact
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $VersionFolder
    )

    $ManifestPath = Join-Path -Path $VersionFolder -ChildPath ('{0}.psd1' -f $ModuleName)

    if (-not (Test-Path -LiteralPath $ManifestPath))
    {
        throw ("No manifest at '{0}'. The version folder does not hold a built module." -f $ManifestPath)
    }

    $Manifest = Import-PowerShellDataFile -LiteralPath $ManifestPath

    # A full release carries no prerelease label at all, so its absence is a value, not a fault.
    $Prerelease = ''

    if ($Manifest.Contains('PrivateData') -and $Manifest.PrivateData.Contains('PSData') -and $Manifest.PrivateData.PSData.Contains('Prerelease'))
    {
        $Prerelease = [string]$Manifest.PrivateData.PSData.Prerelease
    }

    [PSCustomObject]@{
        ManifestPath          = $ManifestPath
        ManifestModuleVersion = [string]$Manifest.ModuleVersion
        ManifestPrerelease    = $Prerelease
    }
}

function Get-ComposedVersion
{
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $ManifestModuleVersion,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $ManifestPrerelease
    )

    if ([string]::IsNullOrEmpty($ManifestPrerelease))
    {
        return $ManifestModuleVersion
    }

    '{0}-{1}' -f $ManifestModuleVersion, $ManifestPrerelease
}

function Compare-FileHashSet
{
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]
        $Expected,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]
        $Actual
    )

    <#
        Both directions, for every caller. Comparing only the expected files would pass a copy
        that GAINED a file, and comparing only the files on disk would pass one that LOST an
        expected file. -Verify and -Compare both decide through this one function, so the rule
        cannot drift between them.
    #>
    $ExpectedByPath = @{}

    foreach ($Entry in $Expected)
    {
        $ExpectedByPath[$Entry.Path] = $Entry.Sha256
    }

    $ActualByPath = @{}

    foreach ($Entry in $Actual)
    {
        $ActualByPath[$Entry.Path] = $Entry.Sha256
    }

    [PSCustomObject]@{
        Missing = @($ExpectedByPath.Keys | Where-Object -FilterScript { -not $ActualByPath.ContainsKey($_) } | Sort-Object)
        Extra   = @($ActualByPath.Keys | Where-Object -FilterScript { -not $ExpectedByPath.ContainsKey($_) } | Sort-Object)
        Changed = @($ExpectedByPath.Keys | Where-Object -FilterScript { $ActualByPath.ContainsKey($_) -and $ActualByPath[$_] -ne $ExpectedByPath[$_] } | Sort-Object)
    }
}

$VersionFolderItem = Get-VersionFolder -Root $Path
$ManifestFact = Get-ManifestFact -VersionFolder $VersionFolderItem.FullName
$ComposedVersion = Get-ComposedVersion -ManifestModuleVersion $ManifestFact.ManifestModuleVersion -ManifestPrerelease $ManifestFact.ManifestPrerelease
$FileHash = @(Get-ArtefactFileHash -VersionFolder $VersionFolderItem.FullName)

if ($FileHash.Count -eq 0)
{
    throw ("The version folder '{0}' holds no files." -f $VersionFolderItem.FullName)
}

if ($Record)
{
    if ([string]::IsNullOrWhiteSpace($ManifestFact.ManifestModuleVersion))
    {
        throw 'The built manifest carries no ModuleVersion, so there is nothing to publish under.'
    }

    <#
        The only cross-check between GitVersion and the manifest that is true on every branch. See
        WHICH VERSION IS PUBLISHED above for why the two labels may legitimately differ.
    #>
    $NumericPart = ($ModuleVersion -split '-', 2)[0]

    if ($NumericPart -ne $ManifestFact.ManifestModuleVersion)
    {
        throw ("GitVersion computed '{0}', whose numeric part is '{1}', but the built manifest carries ModuleVersion '{2}'. The artefact is not the build this job thinks it is." -f $ModuleVersion, $NumericPart, $ManifestFact.ManifestModuleVersion)
    }

    $Meta = [ordered]@{
        Sha                   = $Sha
        ModuleName            = $ModuleName
        ModuleVersion         = $ModuleVersion
        ComposedVersion       = $ComposedVersion
        ModuleVersionFolder   = $VersionFolderItem.Name
        ManifestModuleVersion = $ManifestFact.ManifestModuleVersion
        ManifestPrerelease    = $ManifestFact.ManifestPrerelease
        Files                 = $FileHash
    }

    $MetaPath = Join-Path -Path $Path -ChildPath $MetaFileName

    # WriteAllText, not Set-Content, so the file is UTF-8 without a BOM whatever the host default is.
    [System.IO.File]::WriteAllText($MetaPath, (ConvertTo-Json -InputObject $Meta -Depth 5))

    Write-Host -Object ('Recorded {0} in {1}' -f $MetaFileName, $MetaPath)
    Write-Host -Object ('  commit            {0}' -f $Sha)
    Write-Host -Object ('  GitVersion        {0}' -f $ModuleVersion)
    Write-Host -Object ("  manifest version  {0} (prerelease '{1}')" -f $ManifestFact.ManifestModuleVersion, $ManifestFact.ManifestPrerelease)
    Write-Host -Object ('  publishes as      {0}' -f $ComposedVersion)
    Write-Host -Object ('  version folder    {0}' -f $VersionFolderItem.Name)
    Write-Host -Object ('  files hashed      {0}' -f $FileHash.Count)

    foreach ($Entry in $FileHash)
    {
        Write-Host -Object ('    {0}  {1}' -f $Entry.Sha256, $Entry.Path)
    }

    return
}

$MetaPath = Join-Path -Path $Path -ChildPath $MetaFileName

if (-not (Test-Path -LiteralPath $MetaPath))
{
    throw ("No {0} at '{1}'. The artefact did not come from the -Record step, so nothing about it can be proved." -f $MetaFileName, $MetaPath)
}

$Meta = Get-Content -LiteralPath $MetaPath -Raw | ConvertFrom-Json

Write-Host -Object ("Verifying the artefact under '{0}' against {1}." -f $Path, $MetaFileName)

if ($Meta.Sha -ne $Sha)
{
    throw ("{0} records commit '{1}', but this run is for commit '{2}'. The artefact belongs to a different commit." -f $MetaFileName, $Meta.Sha, $Sha)
}

if ($Meta.ModuleVersionFolder -ne $VersionFolderItem.Name)
{
    throw ("{0} records version folder '{1}', but the artefact holds '{2}'." -f $MetaFileName, $Meta.ModuleVersionFolder, $VersionFolderItem.Name)
}

if ($Meta.ManifestModuleVersion -ne $ManifestFact.ManifestModuleVersion)
{
    throw ("{0} records manifest ModuleVersion '{1}', but the artefact's manifest carries '{2}'." -f $MetaFileName, $Meta.ManifestModuleVersion, $ManifestFact.ManifestModuleVersion)
}

if ($Meta.ManifestPrerelease -ne $ManifestFact.ManifestPrerelease)
{
    throw ("{0} records manifest prerelease '{1}', but the artefact's manifest carries '{2}'." -f $MetaFileName, $Meta.ManifestPrerelease, $ManifestFact.ManifestPrerelease)
}

if ($Meta.ComposedVersion -ne $ComposedVersion)
{
    throw ("{0} records '{1}' as the version to publish, but the artefact's manifest composes to '{2}'." -f $MetaFileName, $Meta.ComposedVersion, $ComposedVersion)
}

$Difference = Compare-FileHashSet -Expected @($Meta.Files) -Actual $FileHash

if ($Difference.Missing.Count -gt 0)
{
    throw ('The artefact is missing {0} recorded file(s): {1}' -f $Difference.Missing.Count, ($Difference.Missing -join ', '))
}

if ($Difference.Extra.Count -gt 0)
{
    throw ('The artefact holds {0} file(s) that were never recorded: {1}' -f $Difference.Extra.Count, ($Difference.Extra -join ', '))
}

if ($Difference.Changed.Count -gt 0)
{
    throw ('The SHA-256 of {0} file(s) does not match what was recorded: {1}' -f $Difference.Changed.Count, ($Difference.Changed -join ', '))
}

Write-Host -Object ('  commit            {0}' -f $Meta.Sha)
Write-Host -Object ('  GitVersion        {0}' -f $Meta.ModuleVersion)
Write-Host -Object ("  manifest version  {0} (prerelease '{1}')" -f $ManifestFact.ManifestModuleVersion, $ManifestFact.ManifestPrerelease)
Write-Host -Object ('  publishes as      {0}' -f $ComposedVersion)
Write-Host -Object ('  files verified    {0}, every SHA-256 matches, none missing and none added' -f $FileHash.Count)
Write-Host -Object ("Verified '{0}'." -f $VersionFolderItem.FullName)

if (-not $Compare)
{
    $VersionFolderItem.FullName
    return
}

<#
    THE PACKAGE THE REPOSITORY SERVES, read back the way a consumer gets it. Save-PSResource
    unpacks the .nupkg and drops NuGet's own packaging parts, which leaves exactly the files of
    the version folder that was published: measured on 2026-10-09 with PSResourceGet 1.0.1 and
    1.2.0, publishing a build into a local repository and saving it back gave the four recorded
    files and nothing else, every SHA-256 equal. So the whole version folder is compared, both
    directions, with no exemption list. The manifest is one of those files, so a package of
    another version cannot match either.
#>
$Version = $Meta.ComposedVersion
$Refusal = 'REFUSING TO TAG.'
$Nothing = 'NOTHING has been tagged and no release was created.'

if ((Test-Path -LiteralPath $DownloadPath) -and @(Get-ChildItem -LiteralPath $DownloadPath -Force).Count -gt 0)
{
    throw ("{0} The download directory '{1}' is not empty, so a package found there could be a stale copy rather than what {2} serves. {3}" -f $Refusal, $DownloadPath, $Repository, $Nothing)
}

$SaveRoot = Join-Path -Path $DownloadPath -ChildPath 'module'
$ReadFailure = $null

try
{
    # PSResourceGet 1.0.1 refuses a -Path that does not exist yet (measured).
    $null = New-Item -ItemType Directory -Path $SaveRoot -Force

    <#
        [x] is an exact version in NuGet range syntax. -Prerelease, or a preview is never found;
        -TrustRepository, or the untrusted PSGallery asks for confirmation and a
        non-interactive run fails; -SkipDependencyCheck, since the dependencies are not what is
        being compared.
    #>
    Save-PSResource -Name $ModuleName -Version ('[{0}]' -f $Version) -Prerelease -Repository $Repository -Path $SaveRoot -SkipDependencyCheck -TrustRepository -ErrorAction 'Stop'

    $PublishedFolder = Get-VersionFolder -Root $DownloadPath
    $PublishedHash = @(Get-ArtefactFileHash -VersionFolder $PublishedFolder.FullName)
}
catch
{
    $ReadFailure = $_.Exception.Message
}

if ($null -ne $ReadFailure)
{
    throw ("{0} Expected to read {1} {2} back from {3} and compare it with the build this run tested for {4}, and could not ({5}). A package that cannot be read cannot be shown to be this commit's build. {6} If the failure was transient, re-run this job: it reads the package again, and tags {4} only if it is this build." -f $Refusal, $ModuleName, $Version, $Repository, $Sha, $ReadFailure, $Nothing)
}

$Published = Compare-FileHashSet -Expected $FileHash -Actual $PublishedHash
$Differences = [System.Collections.Generic.List[string]]::new()

if ($Published.Missing.Count -gt 0)
{
    $Differences.Add(('it lacks {0} file(s) the tested build holds: {1}' -f $Published.Missing.Count, ($Published.Missing -join ', ')))
}

if ($Published.Extra.Count -gt 0)
{
    $Differences.Add(('it holds {0} file(s) the tested build does not: {1}' -f $Published.Extra.Count, ($Published.Extra -join ', ')))
}

if ($Published.Changed.Count -gt 0)
{
    $Differences.Add(('the SHA-256 of {0} file(s) differs from the tested build: {1}' -f $Published.Changed.Count, ($Published.Changed -join ', ')))
}

if ($Differences.Count -gt 0)
{
    $Message = @(
        ('{0} {1} {2} on {3} is not the build this run tested for {4}: {5}.' -f $Refusal, $ModuleName, $Version, $Repository, $Sha, ($Differences -join '; '))
        ('So it was published from another commit, or from another build of this one, and tagging {0} as v{1} would name a package that does not hold this commit''s build. {2}' -f $Sha, $Version, $Nothing)
        ("To repair: find the run on main that published {0} -- its 'Publish to the PowerShell Gallery' step logged 'Publishing {1} {0}', not 'SKIPPING THE PUBLISH' -- and push the tag onto that run's commit by hand: git tag v{0} <commit>, then git push origin v{0}." -f $Version, $ModuleName)
        ('Then re-run ALL jobs of this run, not only the failed ones: the new build counts up from that tag and publishes {0} as the next preview. Re-running only the failed jobs reuses this run''s build, which carries {1}, and is refused again.' -f $Sha, $Version)
        ('If the commit that published {0} is {1} itself, the tag by hand is the whole repair.' -f $Version, $Sha)
    ) -join ' '

    throw $Message
}

Write-Host -Object ("The package {0} serves as {1} {2} is this run's tested build of {3}: {4} files, every SHA-256 matches, none missing and none added." -f $Repository, $ModuleName, $Version, $Sha, $FileHash.Count)
