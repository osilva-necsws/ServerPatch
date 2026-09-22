<#
.SYNOPSIS
    Execute Apache 2.4 patching process.

.DESCRIPTION
    This script executes the Apache 2.4 patching.
    It stops the dynamically detected Apache service(s), replaces the specified directories (bin, lib, modules, etc.)
    and restarts the service.

.NOTES
    Automated patching script structure
#>

[CmdletBinding()]
param(
    [string]$PackagePath = "$env:cpu_PatchApache"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Apache 2.4 Patching" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if (-not $PackagePath -match "^http") {
    if (-not (Test-Path $PackagePath)) {
        Write-Host "Package not found: $PackagePath" -ForegroundColor Red
        exit 1
    }
}

# Dynamically find Apache Services
Write-Host "Searching for Apache services..." -ForegroundColor Cyan
$apacheServices = Get-CimInstance -ClassName Win32_Service -Filter "PathName LIKE '%httpd.exe%'"

if (-not $apacheServices -or $apacheServices.Count -eq 0) {
    Write-Host "⚠ No Apache services found on this server" -ForegroundColor Yellow
    exit 0
}

# Extract the package to a temporary directory once
$TempDir = Join-Path $env:TEMP "ApacheUpdate_$(Get-Date -UFormat %s)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

$downloadPath = Join-Path $TempDir "httpd-package.zip"
Write-Host "Downloading Apache package from Artifactory..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $PackagePath -OutFile $downloadPath -UseBasicParsing

Write-Host "Extracting update package to $TempDir"
Expand-Archive -Path $downloadPath -DestinationPath $TempDir -Force

$successCount = 0

foreach ($service in $apacheServices) {
    $serviceName = $service.Name
    $servicePath = $service.PathName
    $InstallDir = $null

    Write-Host "Processing service: $($serviceName)" -ForegroundColor Cyan
    Write-Host "  Service Path: $servicePath" -ForegroundColor Gray

    # Clean the service path and extract installation directory
    if ($servicePath -match '"?(.+)\\bin\\httpd\.exe"?') {
        $InstallDir = $matches[1].Trim()
    } else {
        Write-Host "  ⚠ Could not parse Apache root from service path" -ForegroundColor Yellow
        continue
    }

    if (-not (Test-Path $InstallDir)) {
        Write-Host "  ⚠ Install directory not found: $InstallDir" -ForegroundColor Red
        continue
    }

    Write-Host "  Install Directory: $InstallDir" -ForegroundColor White

    # 1. Stop the Apache Service
    Write-Host "  Stopping service: $serviceName"
    Stop-Service -Name $serviceName -Force -ErrorAction Stop

    # 2. Replace files/directories (bin, lib, modules)
    $DirsToReplace = @("bin", "lib", "modules")
    foreach ($dir in $DirsToReplace) {
        $SourceDir = Join-Path $TempDir $dir
        $DestDir = Join-Path $InstallDir $dir
        
        if (Test-Path $SourceDir) {
            Write-Host "  Replacing folder: $dir"
            if (Test-Path $DestDir) {
                # Backup or simply remove old dir
                Remove-Item -Path $DestDir -Recurse -Force
            }
            Copy-Item -Path $SourceDir -Destination $InstallDir -Recurse -Force
        }
    }

    # Replace root text files like LICENSE.txt, ABOUT_APACHE.txt, etc if we need
    Get-ChildItem -Path $TempDir -File | ForEach-Object {
        Write-Host "  Replacing file: $($_.Name)"
        Copy-Item -Path $_.FullName -Destination $InstallDir -Force
    }

    # 3. Start the Apache Service
    Write-Host "  Starting service: $serviceName"
    Start-Service -Name $serviceName -ErrorAction Stop
    $successCount++
}

# 4. Cleanup
Remove-Item -Path $TempDir -Recurse -Force

if ($successCount -gt 0) {
    Write-Host "Patching completed successfully for $successCount service(s)!" -ForegroundColor Green
} else {
    Write-Host "No services were successfully patched." -ForegroundColor Yellow
}

$output = @{
    Hostname = $env:COMPUTERNAME
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    PatchSuccess = ($successCount -gt 0)
    PatchedServicesCount = $successCount
}
$baseDir = Split-Path $PSScriptRoot -Parent
$artifactsDir = Join-Path $baseDir "artifacts"
$jsonPath = Join-Path $artifactsDir "apache_patch_complete.json"
$output | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath

exit 0
