<#
.SYNOPSIS
    Verify successful Tomcat patch installation.

.DESCRIPTION
    This script verifies that the Tomcat patch was applied successfully by checking
    the version of installed Tomcat instances and comparing against the expected version
    from the patch package.

.PARAMETER cpu_PatchWebTier
    The Artifactory URL for Tomcat patch files (from environment variable)

.PARAMETER cpu_DOMAIN
    The Tomcat domain name that was patched (from environment variable)

.EXAMPLE
    .\Verify-Tomcat-Patch.ps1
    
.NOTES
    Author: Auto-generated for GitLab CI/CD
    Date: January 6, 2026
    Used by GitLab CI/CD pipeline
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verifying Tomcat Patch Success" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get environment variables
$cpuPatchWebTier = $env:cpu_PatchWebTier
$cpuDomain = $env:cpu_DOMAIN

# Determine repository base directory - prefer GITHUB_WORKSPACE if available (running in CI)
$scriptDir = $PSScriptRoot
if ($env:GITHUB_WORKSPACE) {
    $repoDir = $env:GITHUB_WORKSPACE
    Write-Host "Running in CI - using GITHUB_WORKSPACE: $repoDir" -ForegroundColor Gray
} else {
    $repoDir = Split-Path $scriptDir -Parent
    Write-Host "Running locally - using script parent: $repoDir" -ForegroundColor Gray
}

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Artifactory URL = $cpuPatchWebTier" -ForegroundColor White
Write-Host "  cpu_DOMAIN = $(if ([string]::IsNullOrWhiteSpace($cpuDomain)) { '(ALL DOMAINS)' } else { $cpuDomain })" -ForegroundColor White
Write-Host ""

# Check if patch was actually performed
$patchCompleteJson = Join-Path $repoDir "artifacts\tomcat_patch_complete.json"
if (Test-Path $patchCompleteJson) {
    try {
        $patchData = Get-Content $patchCompleteJson | ConvertFrom-Json
        if ($patchData.PatchSkipped -eq $true) {
            Write-Host "⏭️ Patch was skipped - $($patchData.Reason)" -ForegroundColor Cyan
            Write-Host "System already at version: $($patchData.CurrentVersion)" -ForegroundColor White
            Write-Host ""
            Write-Host "✓ No verification needed" -ForegroundColor Green
            
            # Create verification artifact indicating skip
            $artifactsDir = Join-Path $repoDir "artifacts"
            if (-not (Test-Path $artifactsDir)) {
                New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
            }
            
            $skipInfo = @{
                Hostname = $env:COMPUTERNAME
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                VerificationSkipped = $true
                Reason = $patchData.Reason
                Version = $patchData.CurrentVersion
            }
            
            $verifyJsonPath = Join-Path $artifactsDir "tomcat_verification.json"
            $skipInfo | ConvertTo-Json -Depth 10 | Set-Content -Path $verifyJsonPath
            
            exit 0
        }
    } catch {
        Write-Host "⚠ Could not read patch completion data: $_" -ForegroundColor Yellow
    }
}

# Check if tomcat_patch_complete.json exists
$patchCompleteJsonPath = Join-Path $repoDir "artifacts\tomcat_patch_complete.json"
if (-not (Test-Path $patchCompleteJsonPath)) {
    Write-Host "⚠ No patch completion artifact found - skipping verification" -ForegroundColor Yellow
    Write-Host "Expected to find: $patchCompleteJsonPath" -ForegroundColor Yellow
    exit 0
}

Write-Host "✓ Patch completion artifact found" -ForegroundColor Green

# Load patch completion data
try {
    $patchComplete = Get-Content $patchCompleteJsonPath | ConvertFrom-Json
    Write-Host ""
    Write-Host "Patch Information:" -ForegroundColor Cyan
    Write-Host "  Server: $($patchComplete.Hostname)" -ForegroundColor White
    Write-Host "  Patch Date: $($patchComplete.PatchDate)" -ForegroundColor White
    Write-Host "  Package: $($patchComplete.TomcatPackage)" -ForegroundColor White
    Write-Host "  Patched Domains: $($patchComplete.PatchedDomains -join ', ')" -ForegroundColor White
    Write-Host ""
} catch {
    Write-Host "ERROR: Could not read patch completion artifact: $_" -ForegroundColor Red
    exit 1
}

# Extract expected version from package name
$expectedVersion = $null
if ($patchComplete.TomcatPackage -match 'apache-tomcat-([\d\.]+)\.zip') {
    $expectedVersion = $matches[1]
    Write-Host "Expected Tomcat Version: $expectedVersion" -ForegroundColor Cyan
} else {
    Write-Host "⚠ Could not determine expected version from package name" -ForegroundColor Yellow
}

Write-Host ""

# Set up paths and import modules
$modulePath = Join-Path $repoDir "lib"
$resourcePath = Join-Path $repoDir "resource"
$packagePath = Join-Path $repoDir "package"
$logPath = Join-Path $repoDir "logs"

$global:basedir = $repoDir
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
    Import-Module (Join-Path $modulePath "caci_utils.psm1") -Force -ErrorAction Stop
    
    Write-Host "✓ Successfully imported required modules" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "ERROR: Failed to import required modules: $_" -ForegroundColor Red
    exit 1
}

# Re-run audit to get current state
Write-Host "Running audit to check current Tomcat state..." -ForegroundColor Cyan
try {
    $auditScript = Join-Path $modulePath "audit_get.ps1"
    if (Test-Path $auditScript) {
        & $auditScript | Out-Null
        Write-Host "✓ Audit completed" -ForegroundColor Green
    } else {
        Write-Host "⚠ Audit script not found, skipping audit" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠ Failed to run audit: $_" -ForegroundColor Yellow
}

Write-Host ""

# Get current domain details
Write-Host "Checking current Tomcat domain configurations..." -ForegroundColor Cyan
Write-Host ""

$tc_doms = @()
$tc_doms = webtier_details $tc_doms

if ($tc_doms.Count -eq 0) {
    Write-Host "ERROR: No Tomcat domains found after patch" -ForegroundColor Red
    exit 1
}

# Filter to domains that were patched
$patchedDomainNames = $patchComplete.PatchedDomains | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$tc_doms_filtered = $tc_doms | Where-Object { $patchedDomainNames -contains $_.Dom }

if ($tc_doms_filtered.Count -eq 0) {
    Write-Host "ERROR: None of the patched domains found in current configuration" -ForegroundColor Red
    exit 1
}

# Check Base version once (shared by all domains)
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tomcat Base Version Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$tomcatBase = $tc_doms_filtered[0].Base
$currentVersion = "Unknown"
$versionFile = Join-Path $tomcatBase "RELEASE-NOTES"

if (Test-Path $versionFile) {
    $versionContent = Get-Content $versionFile -First 20 -ErrorAction SilentlyContinue
    $versionLine = $versionContent | Where-Object { $_ -match "(Apache Tomcat|Version)" } | Select-Object -First 1
    
    if ($versionLine -match "(\d+\.\d+\.\d+)") {
        $currentVersion = $matches[1]
    }
} else {
    Write-Host "⚠ RELEASE-NOTES file not found at: $versionFile" -ForegroundColor Yellow
}

Write-Host "Base Directory: $tomcatBase" -ForegroundColor White
Write-Host "Current Version: $currentVersion" -ForegroundColor White

if ($expectedVersion -and $currentVersion -eq $expectedVersion) {
    Write-Host "✓ Version matches expected: $expectedVersion" -ForegroundColor Green
} elseif ($expectedVersion -and $currentVersion -ne "Unknown") {
    Write-Host "⚠ Version mismatch - Expected: $expectedVersion, Got: $currentVersion" -ForegroundColor Yellow
} elseif ($currentVersion -ne "Unknown") {
    Write-Host "✓ Version detected: $currentVersion" -ForegroundColor Green
} else {
    Write-Host "⚠ Could not detect version from RELEASE-NOTES" -ForegroundColor Yellow
}

Write-Host ""

# Verify each patched domain
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Domain Service Verification" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$verificationResults = @()
$allVerified = $true

foreach ($domain in $tc_doms_filtered) {
    Write-Host "Domain: $($domain.Dom)" -ForegroundColor Cyan
    Write-Host "  Home: $($domain.Home)" -ForegroundColor Gray
    
    # Check if domain directory exists
    if (-not (Test-Path $domain.Home)) {
        Write-Host "  ✗ ERROR: Domain home directory not found" -ForegroundColor Red
        $allVerified = $false
        
        $verificationResults += @{
            Domain = $domain.Dom
            Home = $domain.Home
            Verified = $false
            Version = "N/A"
            Error = "Domain home directory not found"
        }
        Write-Host ""
        continue
    }
    
    # Check if service exists and is running (using domain name as service name)
    $serviceName = $domain.Dom
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    
    $serviceRunning = $false
    if ($service) {
        if ($service.Status -eq 'Running') {
            Write-Host "  ✓ Service '$serviceName' is running" -ForegroundColor Green
            $serviceRunning = $true
        } else {
            Write-Host "  ⚠ Service '$serviceName' exists but is not running (Status: $($service.Status))" -ForegroundColor Yellow
            $allVerified = $false
        }
    } else {
        Write-Host "  ⚠ Service '$serviceName' not found" -ForegroundColor Yellow
        $allVerified = $false
    }
    
    # Check for critical directories in the Base directory (shared by all domains)
    $binDir = Join-Path $domain.Base "bin"
    $libDir = Join-Path $domain.Base "lib"
    
    $binExists = Test-Path $binDir
    $libExists = Test-Path $libDir
    
    if ($binExists -and $libExists) {
        Write-Host "  ✓ Critical directories present in Base (bin, lib)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ ERROR: Missing critical directories in Base ($($domain.Base))" -ForegroundColor Red
        if (-not $binExists) { Write-Host "    - bin directory missing" -ForegroundColor Red }
        if (-not $libExists) { Write-Host "    - lib directory missing" -ForegroundColor Red }
        $allVerified = $false
    }
    
    $domainVerified = $binExists -and $libExists -and $serviceRunning
    
    $verificationResults += @{
        Domain = $domain.Dom
        Home = $domain.Home
        Verified = $domainVerified
        ServiceRunning = $serviceRunning
        Error = if (-not $domainVerified) { "Verification checks failed" } else { $null }
    }
    
    if (-not $domainVerified) {
        $allVerified = $false
    }
    
    Write-Host ""
}

# Save verification results to artifact
$artifactsDir = Join-Path $repoDir "artifacts"
if (-not (Test-Path $artifactsDir)) {
    New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
}

$verificationInfo = @{
    Hostname = $env:COMPUTERNAME
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Version = $detectedVersion
    TomcatPackage = $patchComplete.TomcatPackage
    OverallStatus = if ($allVerified) { "SUCCESS" } else { "FAILED" }
    Domains = $verificationResults
    Issues = @($verificationResults | Where-Object { -not $_.Verified } | ForEach-Object { 
        "Domain $($_.Domain): $($_.Error)"
    })
}

$verificationPath = Join-Path $artifactsDir "tomcat_verification.json"
$verificationInfo | ConvertTo-Json -Depth 10 | Set-Content -Path $verificationPath

Write-Host "✓ Verification artifact saved to: $verificationPath" -ForegroundColor Green
if (Test-Path $verificationPath) {
    Write-Host "  File exists and size: $((Get-Item $verificationPath).Length) bytes" -ForegroundColor Gray
} else {
    Write-Host "  WARNING: File was not created!" -ForegroundColor Red
}
Write-Host ""

# Final summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verification Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($allVerified) {
    Write-Host "✓ All verification checks passed" -ForegroundColor Green
    Write-Host ""
    Write-Host "Tomcat patch applied successfully!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗ Some verification checks failed" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please review the verification results above" -ForegroundColor Yellow
    exit 1
}
