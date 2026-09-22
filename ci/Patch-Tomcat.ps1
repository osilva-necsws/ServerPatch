<#
.SYNOPSIS
    Execute Tomcat patching process.

.DESCRIPTION
    This script validates environment variables and executes the Tomcat patching.
    Requires cpu_PatchWebTier and optionally cpu_DOMAIN environment variables to be set.
    If cpu_DOMAIN is not set, patches all detected Tomcat domains.

.PARAMETER cpu_PatchWebTier
    The Artifactory URL for Tomcat patch files (from environment variable)

.PARAMETER cpu_DOMAIN
    The Tomcat domain name to patch (from environment variable). If empty, patches all domains.

.EXAMPLE
    .\Patch-Tomcat.ps1
    
.NOTES
    Author: Auto-generated for GitLab CI/CD
    Date: January 6, 2026
    Used by GitLab CI/CD pipeline
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tomcat WebTier Patching" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get environment variables
$cpuPatchWebTier = $env:cpu_PatchWebTier
$cpuDomain = $env:cpu_DOMAIN

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Artifactory URL = $cpuPatchWebTier" -ForegroundColor White
Write-Host "  cpu_DOMAIN = $(if ([string]::IsNullOrWhiteSpace($cpuDomain)) { '(ALL DOMAINS)' } else { $cpuDomain })" -ForegroundColor White
Write-Host ""

# Determine base directory
$scriptDir = $PSScriptRoot
$baseDir = Split-Path $scriptDir -Parent

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
    foreach ($domain in $tomcatData.TomcatDomains) {
        Write-Host "  - Name: $($domain.Name), Home: $($domain.Home), Version: $($domain.Version)" -ForegroundColor White
    }
    Write-Host ""
} catch {
    Write-Host "⚠ Could not read tomcat_instances.json: $_" -ForegroundColor Yellow
}

# Validate required environment variables
$validationFailed = $false

if ([string]::IsNullOrWhiteSpace($cpuPatchWebTier)) {
    Write-Host "ERROR: cpu_PatchWebTier environment variable is required for Patch Tomcat action" -ForegroundColor Red
    $validationFailed = $true
}

if ($validationFailed) {
    Write-Host ""
    Write-Host "Please set the required environment variables and try again." -ForegroundColor Red
    exit 1
}

Write-Host "✓ All required environment variables are set" -ForegroundColor Green
Write-Host ""

# Set up paths
$modulePath = Join-Path $baseDir "lib"
$resourcePath = Join-Path $baseDir "resource"
# Persistent download cache survives runner workspace cleanup; falls back to in-repo folder for local runs
$packagePath = if ($env:PATCH_CACHE_DIR) { Join-Path $env:PATCH_CACHE_DIR "tomcat" } else { Join-Path $baseDir "package" }
$logPath = Join-Path $baseDir "logs"

# Set global variables for modules
$global:basedir = $baseDir
$global:module_path = $modulePath
$global:resource = $resourcePath
$global:package_path = $packagePath
$global:log_path = $logPath

# Import required modules
Write-Host "Importing required modules..." -ForegroundColor Cyan
try {
    Get-Module | Remove-Module -ErrorAction SilentlyContinue
    
    Import-Module (Join-Path $modulePath "Logging.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulePath "Folder-Ident.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulePath "tomcat_tools.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulePath "tomcat_server_xml.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulePath "caci_utils.psm1") -Force -ErrorAction Stop
    
    Write-Host "✓ Successfully imported required modules" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "ERROR: Failed to import required modules: $_" -ForegroundColor Red
    exit 1
}

# Load version details
$aboutScript = Join-Path $modulePath "About.ps1"
if (Test-Path $aboutScript) {
    . $aboutScript
}

# Download Tomcat pack from Artifactory
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Downloading Tomcat Package from Artifactory" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

try {
    # Use direct URL from cpu_PatchWebTier
    $tomcatZipUrl = $cpuPatchWebTier
    
    # Extract filename from URL
    $tomcatZipFile = Split-Path $tomcatZipUrl -Leaf
    $tomcatPackPath = Join-Path $packagePath $tomcatZipFile
    
    Write-Host "Package Information:" -ForegroundColor Cyan
    Write-Host "  URL: $tomcatZipUrl" -ForegroundColor White
    Write-Host "  File: $tomcatZipFile" -ForegroundColor White
    Write-Host ""
    
    # Ensure package directory exists
    if (-not (Test-Path $packagePath)) {
        New-Item -Path $packagePath -ItemType Directory -Force | Out-Null
    }
    
    # Check if file already exists and verify it
    $needsDownload = $true
    if (Test-Path $tomcatPackPath) {
        Write-Host "Package already exists locally, checking integrity..." -ForegroundColor Cyan
        try {
            # Try to extract version to verify it's a valid zip
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($tomcatPackPath)
            $zip.Dispose()
            Write-Host "✓ Existing package is valid, skipping download" -ForegroundColor Green
            $needsDownload = $false
        } catch {
            Write-Host "⚠ Existing package is corrupt, will re-download" -ForegroundColor Yellow
            Remove-Item $tomcatPackPath -Force -ErrorAction SilentlyContinue
        }
    }
    
    if ($needsDownload) {
        Write-Host "Downloading Tomcat package from: $tomcatZipUrl" -ForegroundColor Cyan
        Write-Host "Downloading to: $tomcatPackPath" -ForegroundColor Gray
        
        # Download with progress
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $tomcatZipUrl -OutFile $tomcatPackPath -UseBasicParsing
        $ProgressPreference = 'Continue'
        
        Write-Host "✓ Downloaded Tomcat package" -ForegroundColor Green
    }
    
    Write-Host ""
    
    # Calculate MD5 for logging purposes
    Write-Host "Calculating package checksum..." -ForegroundColor Cyan
    $actualMD5 = (Get-FileHash -Path $tomcatPackPath -Algorithm MD5).Hash
    Write-Host "  MD5: $actualMD5" -ForegroundColor Gray
    Write-Host ""
    
    # Set global variable for tomcat pack
    $global:tomcat_pack = $tomcatPackPath
    
} catch {
    Write-Host "ERROR: Failed to download Tomcat package: $_" -ForegroundColor Red
    exit 1
}

# Check for pre-existing version match
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Pre-Patch Version Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

try {
    # Extract version from package filename (e.g., apache-tomcat-9.0.90.zip -> 9.0.90)
    if ($tomcatZipFile -match 'apache-tomcat-([\d\.]+)\.zip') {
        $newVersion = $matches[1]
        Write-Host "Package contains Tomcat version: $newVersion" -ForegroundColor Cyan
        
        # Check if any domain already has this version
        $allAlreadyPatched = $true
        foreach ($domain in $tomcatData.TomcatDomains) {
            if ($domain.Version -ne $newVersion) {
                $allAlreadyPatched = $false
                break
            }
        }
        
        if ($allAlreadyPatched) {
            Write-Host ""
            Write-Host "⚠ All Tomcat domains are already at version $newVersion" -ForegroundColor Yellow
            Write-Host "Skipping patch as system is already up-to-date" -ForegroundColor Yellow
            
            # Create artifact indicating no patch was needed
            $artifactsDir = Join-Path $baseDir "artifacts"
            if (-not (Test-Path $artifactsDir)) {
                New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
            }
            
            $skipInfo = @{
                Hostname = $env:COMPUTERNAME
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                PatchSkipped = $true
                Reason = "Already at target version"
                CurrentVersion = $newVersion
                TargetVersion = $newVersion
            }
            
            $skipJsonPath = Join-Path $artifactsDir "tomcat_patch_complete.json"
            $skipInfo | ConvertTo-Json -Depth 10 | Set-Content -Path $skipJsonPath
            
            Write-Host ""
            Write-Host "✓ Status recorded in artifact" -ForegroundColor Green
            exit 0
        }
    }
} catch {
    Write-Host "⚠ Could not determine version from package name, continuing with patch" -ForegroundColor Yellow
}

Write-Host ""

# Get domain details using audit
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Discovering Domain Configuration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$tc_doms = @()
$tc_doms = webtier_details $tc_doms

if ($tc_doms.Count -eq 0) {
    Write-Host "ERROR: No Tomcat domains found" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($tc_doms.Count) domain(s)" -ForegroundColor Green
Write-Host ""

# Filter to specific domain if specified
if (-not [string]::IsNullOrWhiteSpace($cpuDomain)) {
    Write-Host "Filtering to specific domain: $cpuDomain" -ForegroundColor Cyan
    $tc_doms = $tc_doms | Where-Object { $_.Dom -eq $cpuDomain }
    
    if ($tc_doms.Count -eq 0) {
        Write-Host "ERROR: Specified domain '$cpuDomain' not found" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✓ Found matching domain" -ForegroundColor Green
    Write-Host ""
}

# Display banner and confirmation message
$banner_width = 55

Write-Host ""
Write-Host ("-" * $banner_width) -ForegroundColor Yellow
Write-Host "  ChildView WebTier Patch" -ForegroundColor Yellow
Write-Host "  ===========================" -ForegroundColor Yellow
Write-Host "  CRITICAL: Ensure server backup completed" -ForegroundColor Yellow
Write-Host "  CRITICAL: Ensure all users are logged out" -ForegroundColor Yellow
Write-Host "  ===========================" -ForegroundColor Yellow
Write-Host "  Note: WebTiers can be shared between Live/Test" -ForegroundColor Yellow
Write-Host "  Updating Test COULD impact Live systems!" -ForegroundColor Yellow
Write-Host ("-" * $banner_width) -ForegroundColor Yellow
Write-Host ""

Write-Host "Domains to be patched:" -ForegroundColor Cyan
foreach ($domain in $tc_doms) {
    Write-Host "  - $($domain.Dom) [$($domain.Home)]" -ForegroundColor White
}
Write-Host ""

# Application replacement phase
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Phase 1: Application Replacement" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($webtier in $tc_doms) {
    if ($webtier.Home) {
        Write-Host "Processing domain: $($webtier.Dom)" -ForegroundColor Cyan
        tomcat_app_replacement $webtier.Home $webtier.Dom
        Write-Host "✓ Application replacement complete for $($webtier.Dom)" -ForegroundColor Green
        Write-Host ""
    }
}

# Update Tomcat (stop services, update software, patch configs, restart services)
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Phase 2: Update Tomcat" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

update_tomcat $tc_doms

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tomcat Patching Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "✓ All Tomcat domains patched successfully" -ForegroundColor Green
Write-Host ""

# Create completion artifact
$artifactsDir = Join-Path $baseDir "artifacts"
if (-not (Test-Path $artifactsDir)) {
    New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
}

$completionInfo = @{
    Hostname = $env:COMPUTERNAME
    PatchDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    PatchedDomains = @($tc_doms | ForEach-Object { $_.Dom })
    TomcatPackage = $tomcatZipFile
    ArtifactoryURL = $cpuPatchWebTier
}

$completionPath = Join-Path $artifactsDir "tomcat_patch_complete.json"
$completionInfo | ConvertTo-Json -Depth 10 | Set-Content -Path $completionPath

Write-Host "Patch completion artifact saved to: $completionPath" -ForegroundColor Gray
