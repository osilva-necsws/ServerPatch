<#
.SYNOPSIS
    Silent install/update of 7-Zip with specified options.
.DESCRIPTION
    Downloads and installs the latest 7-Zip from Artifactory with silent installation.
.EXAMPLE
    .\Patch-7Zip.ps1
.NOTES
    Author: Pipeline Orchestrator (Adapted for CPUTOMCAT)
    Date: July 16, 2026
#>

[CmdletBinding()]
param(
    [string]$PackagePath = $env:cpu_Patch7Zip
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "7-Zip Silent Update/Install" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check if 7-Zip is already installed
Write-Host "Checking for existing 7-Zip installation..." -ForegroundColor Cyan
$7zipPath = $null

# Check common installation paths for 7-Zip
$potentialPaths = @(
    "${env:ProgramFiles}\7-Zip\7z.exe",
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
)

foreach ($path in $potentialPaths) {
    if (Test-Path $path) {
        $7zipPath = $path
        break
    }
}

if ($7zipPath) {
    try {
        $versionInfo = (Get-Item $7zipPath).VersionInfo
        $currentVersion = $versionInfo.FileVersion
        Write-Host "7-Zip is already installed at: $7zipPath (Version: $currentVersion)" -ForegroundColor Yellow
    } catch {
        Write-Host "7-Zip is already installed at: $7zipPath" -ForegroundColor Yellow
    }
    Write-Host "Proceeding with installation to update/reinstall..." -ForegroundColor Cyan
} else {
    Write-Host "7-Zip is not currently installed. Proceeding with installation..." -ForegroundColor Cyan
}

# Close 7-Zip processes if they are running to avoid file locks
Write-Host "Checking for running 7-Zip processes..." -ForegroundColor Cyan
$7zipProcesses = Get-Process -Name "7zFM", "7z" -ErrorAction SilentlyContinue
if ($7zipProcesses) {
    Write-Host "  Closing $($7zipProcesses.Count) running 7-Zip process(es)..." -ForegroundColor Yellow
    $7zipProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# Create temporary folder in runner directory
$artifactsDir = Join-Path $PSScriptRoot "..\artifacts"
if (!(Test-Path $artifactsDir)) {
    New-Item -ItemType Directory -Path $artifactsDir -Force | Out-Null
}

$tempDir = Join-Path $PSScriptRoot "..\temp"
if (!(Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

$installerPath = Join-Path $tempDir "7z-x64.exe"

if (-not $PackagePath) {
    $PackagePath = "https://artifactory.cyp.caci.co.uk:8051/artifactory/softwareRepo/tools-generic-local/7zip/latest/7z-x64.exe"
}

Write-Host "Downloading 7-Zip installer from Artifactory..." -ForegroundColor Cyan
Write-Host "  URL: $PackagePath" -ForegroundColor Gray

# Check if curl is available
$curlAvailable = $null -ne (Get-Command curl -ErrorAction SilentlyContinue)

if ($curlAvailable) {
    Write-Host "Using curl for download..." -ForegroundColor Gray
    curl --ssl-no-revoke --insecure -L -o $installerPath $PackagePath
} else {
    Write-Host "curl not found, using PowerShell Invoke-WebRequest..." -ForegroundColor Gray
    try {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        Invoke-WebRequest -Uri $PackagePath -OutFile $installerPath -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
    } catch {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        Invoke-WebRequest -Uri $PackagePath -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
    } finally {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
    }
}

if (!(Test-Path $installerPath)) {
    Write-Host "ERROR: 7-Zip installer was not downloaded successfully." -ForegroundColor Red
    exit 1
}

$fileInfo = Get-Item $installerPath
Write-Host "Downloaded file size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -ForegroundColor Gray

if ($fileInfo.Length -lt 100KB) {
    Write-Host "ERROR: Downloaded file is too small to be a valid installer. Check the URL." -ForegroundColor Red
    Remove-Item $installerPath -ErrorAction SilentlyContinue
    exit 1
}

# 7-Zip silent install arguments (/S for silent)
$installArgs = @("/S")

Write-Host "Installing 7-Zip silently..." -ForegroundColor Cyan

try {
    $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Write-Host "WARNING: Installer returned non-zero exit code: $($process.ExitCode)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Failed to run 7-Zip installer: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item $installerPath -ErrorAction SilentlyContinue
    exit 1
}

Remove-Item $installerPath -ErrorAction SilentlyContinue

# Verify installation
Write-Host "Verifying 7-Zip installation..." -ForegroundColor Cyan

$installedSuccessfully = $false
foreach ($path in $potentialPaths) {
    if (Test-Path $path) {
        try {
            $versionInfo = (Get-Item $path).VersionInfo
            $newVersion = $versionInfo.FileVersion
            Write-Host "SUCCESS: 7-Zip installed successfully!" -ForegroundColor Green
            Write-Host "  Location: $path" -ForegroundColor Cyan
            Write-Host "  Version: $newVersion" -ForegroundColor Cyan
            $installedSuccessfully = $true
        } catch {
            Write-Host "SUCCESS: 7-Zip installed, but version info unavailable." -ForegroundColor Green
            $installedSuccessfully = $true
        }
        break
    }
}

if (-not $installedSuccessfully) {
    Write-Host "ERROR: 7-Zip installation failed or executable not found in expected locations." -ForegroundColor Red
    exit 1
}

# Create artifact
$patchResult = @{
    Hostname = $env:COMPUTERNAME
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Action = "Patch 7-Zip"
    Status = "Success"
    Version = $newVersion
    Path = $path
}

$patchResult | ConvertTo-Json | Set-Content (Join-Path $artifactsDir "7zip_patch_complete.json")

Write-Host "7-Zip patch process completed." -ForegroundColor Green
