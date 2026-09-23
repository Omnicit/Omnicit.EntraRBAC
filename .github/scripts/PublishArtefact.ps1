#Requires -Version 7.2

<#
    .SYNOPSIS
        Records the module build that the test matrix proved, and later verifies a downloaded copy
        of it file by file.

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

        -Path is, in both modes, the directory that CONTAINS module/<name>/<version>. That is
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

    .EXAMPLE
        ./.github/scripts/PublishArtefact.ps1 -Record -Path 'output' -Sha $env:GITHUB_SHA -ModuleVersion $env:ModuleVersion

    .EXAMPLE
        $ModulePath = ./.github/scripts/PublishArtefact.ps1 -Verify -Path 'artefact' -Sha $env:GITHUB_SHA
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Write-Host goes to the information stream, so the workflow log gets the narration while the version folder path stays this script''s only PIPELINE output -- which is what lets a caller write $ModulePath = ./PublishArtefact.ps1 -Verify. Write-Output would hand the caller the narration as well.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Verify',
    Justification = 'Switch is a parameter-set discriminator; the script branches on $Record and -Verify selects the other set.')]
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true, ParameterSetName = 'Record')]
    [switch]
    $Record,

    [Parameter(Mandatory = $true, ParameterSetName = 'Verify')]
    [switch]
    $Verify,

    [Parameter(Mandatory = $true)]
    [string]
    $Path,

    [Parameter(Mandatory = $true)]
    [string]
    $Sha,

    [Parameter(Mandatory = $true, ParameterSetName = 'Record')]
    [string]
    $ModuleVersion
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

<#
    Both directions. Comparing only the recorded files would pass an artefact that GAINED a file,
    and comparing only the files on disk would pass one that LOST a recorded file.
#>
$RecordedByPath = @{}

foreach ($Entry in @($Meta.Files))
{
    $RecordedByPath[$Entry.Path] = $Entry.Sha256
}

$ActualByPath = @{}

foreach ($Entry in $FileHash)
{
    $ActualByPath[$Entry.Path] = $Entry.Sha256
}

$Missing = @($RecordedByPath.Keys | Where-Object -FilterScript { -not $ActualByPath.ContainsKey($_) } | Sort-Object)

if ($Missing.Count -gt 0)
{
    throw ('The artefact is missing {0} recorded file(s): {1}' -f $Missing.Count, ($Missing -join ', '))
}

$Extra = @($ActualByPath.Keys | Where-Object -FilterScript { -not $RecordedByPath.ContainsKey($_) } | Sort-Object)

if ($Extra.Count -gt 0)
{
    throw ('The artefact holds {0} file(s) that were never recorded: {1}' -f $Extra.Count, ($Extra -join ', '))
}

$Changed = @($RecordedByPath.Keys | Where-Object -FilterScript { $ActualByPath[$_] -ne $RecordedByPath[$_] } | Sort-Object)

if ($Changed.Count -gt 0)
{
    throw ('The SHA-256 of {0} file(s) does not match what was recorded: {1}' -f $Changed.Count, ($Changed -join ', '))
}

Write-Host -Object ('  commit            {0}' -f $Meta.Sha)
Write-Host -Object ('  GitVersion        {0}' -f $Meta.ModuleVersion)
Write-Host -Object ("  manifest version  {0} (prerelease '{1}')" -f $ManifestFact.ManifestModuleVersion, $ManifestFact.ManifestPrerelease)
Write-Host -Object ('  publishes as      {0}' -f $ComposedVersion)
Write-Host -Object ('  files verified    {0}, every SHA-256 matches, none missing and none added' -f $FileHash.Count)
Write-Host -Object ("Verified '{0}'." -f $VersionFolderItem.FullName)

$VersionFolderItem.FullName
