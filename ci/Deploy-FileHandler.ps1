<#
.SYNOPSIS
    Deploy FileHandler.war to Tomcat cv_maint domain.

.DESCRIPTION
    This script downloads FileHandler.war from the configured FILEHANDLER_URL (if set)
    and deploys it to the cv_maint domain webapps folder.
    It performs safe checks:
    - Only deploys to cv_maint.
    - Only deploys if file is missing in destination.
    - Does not overwrite or delete existing files.
    - Reports success/failure but exits 0 (non-blocking) by default unless critical error.

.PARAMETER FILEHANDLER_URL
    Environment variable containing the Artifactory URL for FileHandler.war.

.EXAMPLE
    .\Deploy-FileHandler.ps1
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FileHandler Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$fileHandlerUrl = $env:FILEHANDLER_URL
$scriptDir = $PSScriptRoot
$baseDir = Split-Path $scriptDir -Parent
$packagePath = Join-Path $baseDir "package"
$modulePath = Join-Path $baseDir "lib"
$logPath = Join-Path $baseDir "logs"
$resourcePath = Join-Path $baseDir "resource"

# Set global variables for modules (Matching Patch-Tomcat.ps1 pattern)
$global:basedir = $baseDir
$global:module_path = $modulePath
$global:resource = $resourcePath
$global:package_path = $packagePath
$global:log_path = $logPath


# Check URL
if ([string]::IsNullOrWhiteSpace($fileHandlerUrl)) {
    Write-Host "NOTE: FILEHANDLER_URL environment variable is not set." -ForegroundColor Yellow
    Write-Host "Skipping FileHandler deployment." -ForegroundColor Gray
    exit 0
}

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  FileHandler URL = $fileHandlerUrl" -ForegroundColor White
Write-Host ""
# Check if tomcat_instances.json exists (from previous job)
$tomcatJsonPath = Join-Path $baseDir "artifacts\tomcat_instances.json"
if (-not (Test-Path $tomcatJsonPath)) {
    Write-Host "⚠ No Tomcat instances detected - skipping patch" -ForegroundColor Yellow
    Write-Host "Expected to find: $tomcatJsonPath" -ForegroundColor Yellow
    exit 0
}

Write-Host "✓ Tomcat instances detected at: $tomcatJsonPath" -ForegroundColor Green

# Display detected Tomcat domains
try {
    $tomcatData = Get-Content $tomcatJsonPath | ConvertFrom-Json
    Write-Host ""
    Write-Host "Detected Tomcat Domains:" -ForegroundColor Cyan
    $tc_doms = @()
    foreach ($domain in $tomcatData.TomcatDomains) {
        Write-Host "  - Name: $($domain.Name), Home: $($domain.Home)" -ForegroundColor White
        # Reconstruct object similar to what webtier_details produces for compatibility if needed, 
        # but for this script we just need the Home path.
        $tc_doms += [PSCustomObject]@{
            Dom = $domain.Name
            Home = $domain.Home
            Base = $domain.Base
        }
    }
    Write-Host ""
} catch {
    Write-Host "⚠ Could not read tomcat_instances.json: $_" -ForegroundColor Yellow
    exit 1
}

# Import modules (needed for discovery)
Write-Host "Importing required modules..." -ForegroundColor Cyan
try {
    Import-Module (Join-Path $modulePath "Logging.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulePath "Folder-Ident.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulePath "tomcat_tools.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulePath "caci_utils.psm1") -Force -ErrorAction Stop
    Write-Host "✓ Modules imported" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to import modules: $_" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Download
try {
    if (-not (Test-Path $packagePath)) {
        New-Item -Path $packagePath -ItemType Directory -Force | Out-Null
    }

    $fileName = Split-Path $fileHandlerUrl -Leaf
    $destFile = Join-Path $packagePath $fileName
    
    Write-Host "Downloading FileHandler..." -ForegroundColor Cyan
    Write-Host "  Source: $fileHandlerUrl" -ForegroundColor Gray
    Write-Host "  Dest:   $destFile" -ForegroundColor Gray
    
    Invoke-WebRequest -Uri $fileHandlerUrl -OutFile $destFile -UseBasicParsing
    
    if (-not (Test-Path $destFile)) {
        throw "Download failed, file not created."
    }
    
    Write-Host "✓ Download complete" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "ERROR: Failed to download FileHandler: $_" -ForegroundColor Red
    exit 1
}

# Discovery using JSON artifact instead of re-running audit
Write-Host "Using discovered Tomcat domains..." -ForegroundColor Cyan

# Deployment
Write-Host "Deploying to cv_maint..." -ForegroundColor Cyan
$deployed = $false

foreach ($domain in $tc_doms) {
    if ($domain.Dom -eq "cv_maint") {
        $webapps = Join-Path $domain.Home "webapps"
        $targetWar = Join-Path $webapps $fileName
        
        Write-Host "  Target: $targetWar" -ForegroundColor Gray
        
        if (Test-Path $targetWar) {
            Write-Host "  ⚠ FileHandler.war already exists. Skipping." -ForegroundColor Yellow
        } else {
            if (Test-Path $webapps) {
                Copy-Item -Path $destFile -Destination $targetWar -ErrorAction Stop
                Write-Host "  ✓ Deployed FileHandler.war" -ForegroundColor Green
                $deployed = $true
            } else {
                 Write-Host "  ERROR: webapps folder not found at $webapps" -ForegroundColor Red
            }
        }
    }
}

if (-not $deployed) {
    Write-Host ""
    Write-Host "NOTE: cv_maint domain not found or file already existed." -ForegroundColor Gray
}

Write-Host ""
Write-Host "FileHandler deployment process finished." -ForegroundColor Cyan
exit 0
