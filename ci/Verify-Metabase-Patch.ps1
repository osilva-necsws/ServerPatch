<#
.SYNOPSIS
    Verify successful Metabase patch installation.

.DESCRIPTION
    This script verifies that the Metabase patch was applied successfully by checking
    the service status, JAR file, and winsw.xml configuration for Java 21.

.PARAMETER cpu_PatchMetabase
    The Artifactory URL for Metabase patch files (from environment variable)

.EXAMPLE
    .\Verify-Metabase-Patch.ps1
    
.NOTES
    Author: Auto-generated for GitLab CI/CD
    Date: January 22, 2026
    Used by GitLab CI/CD pipeline
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verifying Metabase Patch Success" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get environment variables
$cpuPatchMetabase = $env:cpu_PatchMetabase

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
Write-Host "  Artifactory URL = $cpuPatchMetabase" -ForegroundColor White
Write-Host ""

# Check if patch was actually performed
$patchCompleteJsonPath = Join-Path $repoDir "artifacts\metabase_patch_complete.json"
if (Test-Path $patchCompleteJsonPath) {
    try {
        $patchData = Get-Content $patchCompleteJsonPath | ConvertFrom-Json
        if ($patchData.PatchSkipped -eq $true) {
            Write-Host "⏭️ Patch was skipped - $($patchData.Reason)" -ForegroundColor Cyan
            if ($patchData.CurrentVersion) {
                Write-Host "System already at version: $($patchData.CurrentVersion)" -ForegroundColor White
            }
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
            }
            if ($patchData.CurrentVersion) {
                $skipInfo.Version = $patchData.CurrentVersion
            }
            
            $verifyJsonPath = Join-Path $artifactsDir "metabase_verification.json"
            $skipInfo | ConvertTo-Json -Depth 10 | Set-Content -Path $verifyJsonPath
            
            exit 0
        }
    } catch {
        Write-Host "⚠ Could not read patch completion data: $_" -ForegroundColor Yellow
    }
}

# Check if metabase_patch_complete.json exists
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
    Write-Host "  Package: $($patchComplete.MetabasePackage)" -ForegroundColor White
    Write-Host "  Patched Instances: $($patchComplete.SuccessCount)" -ForegroundColor White
    Write-Host "  Failed Instances: $($patchComplete.FailedCount)" -ForegroundColor $(if ($patchComplete.FailedCount -gt 0) { "Red" } else { "White" })
    Write-Host ""
} catch {
    Write-Host "ERROR: Could not read patch completion artifact: $_" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verifying Metabase Instances" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$instanceVerifications = @()

foreach ($patchedInst in $patchComplete.PatchedInstances) {
    Write-Host "Verifying: $($patchedInst.ServiceName)" -ForegroundColor Cyan
    Write-Host ""
    
    $verificationResult = @{
        ServiceName = $patchedInst.ServiceName
        ServiceRunning = $false
        JarExists = $false
        JarSize = 0
        MetabaseVersion = "Unknown"
        WinswXmlExists = $false
        JavaVersion = "Unknown"
        JavaVersionCorrect = $false
        PluginsDeleted = $patchedInst.PluginsDeleted
        OJDBCDeployed = $patchedInst.OJDBCDeployed
        Issues = @()
    }
    
    # Check service status
    $service = Get-Service -Name $patchedInst.ServiceName -ErrorAction SilentlyContinue
    
    if ($service) {
        Write-Host "  Service Status: $($service.Status)" -ForegroundColor White
        
        if ($service.Status -eq 'Running') {
            Write-Host "  ✓ Service is running" -ForegroundColor Green
            $verificationResult.ServiceRunning = $true
        } else {
            Write-Host "  ✗ Service not running (Status: $($service.Status))" -ForegroundColor Red
            $verificationResult.Issues += "Service not running"
        }
    } else {
        Write-Host "  ✗ Service not found" -ForegroundColor Red
        $verificationResult.Issues += "Service not found"
    }
    
    # Check JAR file
    $jarPath = Join-Path $patchedInst.InstallationRoot "metabase.jar"
    
    if (Test-Path $jarPath) {
        $jarItem = Get-Item $jarPath
        $jarSizeMB = [math]::Round($jarItem.Length / 1MB, 2)
        $verificationResult.JarExists = $true
        $verificationResult.JarSize = $jarItem.Length
        
        Write-Host "  ✓ metabase.jar exists ($jarSizeMB MB)" -ForegroundColor Green
        
        # Read version from versions.xml
        $versionsXmlPath = Join-Path $patchedInst.InstallationRoot "versions.xml"
        if (Test-Path $versionsXmlPath) {
            try {
                [xml]$versionsXml = Get-Content $versionsXmlPath
                $verificationResult.MetabaseVersion = $versionsXml.versions.metabase
                Write-Host "  ✓ Metabase version: $($versionsXml.versions.metabase)" -ForegroundColor Green
            } catch {
                Write-Host "  ⚠ Could not parse versions.xml: $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  ⚠ versions.xml not found" -ForegroundColor Yellow
        }
        
        # Compare with expected size
        if ($patchedInst.NewJarSize -and $jarItem.Length -ne $patchedInst.NewJarSize) {
            $expectedSizeMB = [math]::Round($patchedInst.NewJarSize / 1MB, 2)
            Write-Host "  ⚠ JAR size mismatch - Expected: $expectedSizeMB MB, Got: $jarSizeMB MB" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ✗ metabase.jar not found" -ForegroundColor Red
        $verificationResult.Issues += "JAR file not found"
    }
    
    # Check winsw.xml (always in winsw subdirectory)
    $winswXmlPath = Join-Path $patchedInst.InstallationRoot "winsw\winsw.xml"
    
    if (Test-Path $winswXmlPath) {
        $verificationResult.WinswXmlExists = $true
        
        try {
            [xml]$winswConfig = Get-Content $winswXmlPath
            $javaExecutable = $winswConfig.service.executable
            
            if ($javaExecutable -match 'jdk-?21' -or $javaExecutable -match 'java.*21') {
                $verificationResult.JavaVersion = "21"
                $verificationResult.JavaVersionCorrect = $true
                Write-Host "  ✓ Java 21 detected" -ForegroundColor Green
            } elseif ($javaExecutable -match 'jdk-?(\d+)') {
                $verificationResult.JavaVersion = $matches[1]
                $verificationResult.JavaVersionCorrect = $false
                Write-Host "  ⚠ Java version $($matches[1]) detected (expected 21)" -ForegroundColor Yellow
                $verificationResult.Issues += "Java version not 21 (found: $($matches[1]))"
            } else {
                $verificationResult.JavaVersion = "Unknown"
                Write-Host "  ⚠ Could not determine Java version" -ForegroundColor Yellow
                $verificationResult.Issues += "Java version unclear"
            }
        } catch {
            Write-Host "  ✗ Failed to parse winsw.xml: $_" -ForegroundColor Red
            $verificationResult.Issues += "Failed to parse winsw.xml"
        }
    } else {
        Write-Host "  ✗ winsw.xml not found" -ForegroundColor Red
        $verificationResult.Issues += "winsw.xml not found"
    }
    
    $instanceVerifications += $verificationResult
    Write-Host ""
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verification Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$successCount = 0
$failedCount = 0
$warningCount = 0

foreach ($verification in $instanceVerifications) {
    $hasIssues = $verification.Issues.Count -gt 0
    $isCriticalFailure = (-not $verification.ServiceRunning) -or (-not $verification.JarExists)
    
    if ($isCriticalFailure) {
        $failedCount++
        Write-Host "✗ $($verification.ServiceName): FAILED" -ForegroundColor Red
    } elseif ($hasIssues) {
        $warningCount++
        Write-Host "⚠ $($verification.ServiceName): WARNING" -ForegroundColor Yellow
    } else {
        $successCount++
        Write-Host "✓ $($verification.ServiceName): SUCCESS" -ForegroundColor Green
    }
    
    # Display plugin/OJDBC status
    if ($verification.PluginsDeleted -eq $true) {
        Write-Host "  ✓ Plugins folder refreshed" -ForegroundColor Gray
    } elseif ($verification.PluginsDeleted -eq $false) {
        Write-Host "  ⚠ Plugins folder not refreshed (locked files)" -ForegroundColor Gray
    }
    
    if ($verification.OJDBCDeployed -eq $true) {
        Write-Host "  ✓ OJDBC deployed" -ForegroundColor Gray
    } elseif ($verification.OJDBCDeployed -eq $false -and $verification.PluginsDeleted -eq $false) {
        Write-Host "  ⚠ OJDBC deployment skipped (plugins not refreshed)" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "Total Verified: $($instanceVerifications.Count)" -ForegroundColor White
Write-Host "  Success: $successCount" -ForegroundColor Green
Write-Host "  Warnings: $warningCount" -ForegroundColor Yellow
Write-Host "  Failed: $failedCount" -ForegroundColor Red

# Create verification artifact
$artifactsDir = Join-Path $repoDir "artifacts"
if (-not (Test-Path $artifactsDir)) {
    New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
}

$verificationInfo = @{
    Hostname = $env:COMPUTERNAME
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    MetabasePackage = $patchComplete.MetabasePackage
    VerificationCount = $instanceVerifications.Count
    SuccessCount = $successCount
    WarningCount = $warningCount
    FailedCount = $failedCount
    Verifications = $instanceVerifications
    OverallStatus = if ($failedCount -eq 0) { "SUCCESS" } else { "FAILED" }
}

$verificationPath = Join-Path $artifactsDir "metabase_verification.json"
$verificationInfo | ConvertTo-Json -Depth 10 | Set-Content -Path $verificationPath

Write-Host ""
Write-Host "✓ Verification artifact saved to: $verificationPath" -ForegroundColor Green
Write-Host "  File size: $((Get-Item $verificationPath).Length) bytes" -ForegroundColor Gray
Write-Host ""

if ($failedCount -eq 0) {
    Write-Host "✓ All Metabase instances verified successfully!" -ForegroundColor Green
    if ($warningCount -gt 0) {
        Write-Host "⚠ $warningCount instance(s) have warnings (review above)" -ForegroundColor Yellow
    }
    exit 0
} else {
    Write-Host "✗ $failedCount instance(s) failed critical verification checks" -ForegroundColor Red
    Write-Host "Review the failures above for details." -ForegroundColor Red
    exit 1
}

Write-Host ""

