<#
.SYNOPSIS
    Fetch a patch package from the GitHub Packages Maven registry into package/.

.DESCRIPTION
    Replaces the old Artifactory download step. Resolves one artifact
    (groupId:artifactId:version:type:classifier) via `mvn dependency:copy` and
    renames the result to the exact filename expected by the ci/Patch-*.ps1 scripts.
    Skips the fetch entirely if the destination file already exists locally.

.EXAMPLE
    ./ci/Get-MavenPackage.ps1 -Classifier tomcat -Type zip -Version 19.32.0 -DestFileName tomcat-package.zip
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Classifier,
    [Parameter(Mandatory)][string]$Type,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$DestFileName,
    [string]$GroupId = "uk.co.caci.childview",
    [string]$ArtifactId = "patch-packages"
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$packageDir = Join-Path $repoRoot "package"
$pomFile = Join-Path $repoRoot "maven\pom.xml"
$settingsFile = Join-Path $repoRoot "maven\settings.xml"

if (-not (Test-Path $packageDir)) {
    New-Item -Path $packageDir -ItemType Directory -Force | Out-Null
}

$destPath = Join-Path $packageDir $DestFileName
if (Test-Path $destPath) {
    Write-Host "✓ Already present locally, skipping Maven fetch: $destPath" -ForegroundColor Green
    exit 0
}

$artifactCoord = "${GroupId}:${ArtifactId}:${Version}:${Type}:${Classifier}"
Write-Host "Fetching $artifactCoord from GitHub Packages..." -ForegroundColor Cyan

& mvn -B -f $pomFile -s $settingsFile dependency:copy `
    "-Dartifact=$artifactCoord" `
    "-DoutputDirectory=$packageDir" `
    "-Dmdep.useBaseVersion=true"

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Maven failed to fetch $artifactCoord" -ForegroundColor Red
    exit 1
}

$downloaded = Get-ChildItem -Path $packageDir -Filter "$ArtifactId-*-$Classifier.$Type" -File | Select-Object -First 1
if (-not $downloaded) {
    Write-Host "ERROR: Downloaded artifact not found in $packageDir (expected pattern: $ArtifactId-*-$Classifier.$Type)" -ForegroundColor Red
    exit 1
}

Rename-Item -Path $downloaded.FullName -NewName $DestFileName -Force
Write-Host "✓ Package ready at: $destPath" -ForegroundColor Green
