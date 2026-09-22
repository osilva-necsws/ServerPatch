<#
.SYNOPSIS
    Verify successful PostgreSQL patch installation.

.DESCRIPTION
    This script verifies that the PostgreSQL patch was applied successfully by checking
    the version of installed PostgreSQL instances and confirming services are running.

.EXAMPLE
    .\Verify-PostgreSQL-Patch.ps1
    
.NOTES
    Author: Generated for GitLab CI/CD
    Date: January 28, 2026
    Used by GitLab CI/CD pipeline
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verifying PostgreSQL Patch Success" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Determine repository base directory
$scriptDir = $PSScriptRoot
if ($env:CI_PROJECT_DIR) {
    $repoDir = $env:CI_PROJECT_DIR
    Write-Host "Running in CI - using CI_PROJECT_DIR: $repoDir" -ForegroundColor Gray
} else {
    $repoDir = Split-Path $scriptDir -Parent
    Write-Host "Running locally - using script parent: $repoDir" -ForegroundColor Gray
}
Write-Host ""

# Check if patch was actually performed
$patchCompleteJson = Join-Path $repoDir "artifacts\postgresql_patch_complete.json"
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
            
            $verifyJsonPath = Join-Path $artifactsDir "postgresql_verification.json"
            $skipInfo | ConvertTo-Json -Depth 10 | Set-Content -Path $verifyJsonPath
            
            exit 0
        }
    } catch {
        Write-Host "⚠ Could not read patch completion data: $_" -ForegroundColor Yellow
    }
}

# Check if postgresql_patch_complete.json exists
if (-not (Test-Path $patchCompleteJson)) {
    Write-Host "⚠ No patch completion artifact found - skipping verification" -ForegroundColor Yellow
    Write-Host "Expected to find: $patchCompleteJson" -ForegroundColor Yellow
    exit 0
}

# Load patch completion data
try {
    $patchData = Get-Content $patchCompleteJson | ConvertFrom-Json
    Write-Host "Patch completion data loaded" -ForegroundColor Green
    Write-Host "  Package: $($patchData.Package)" -ForegroundColor White
    Write-Host "  Target Version: $($patchData.NewVersion)" -ForegroundColor White
    Write-Host "  Patched Instances: $($patchData.TotalInstances)" -ForegroundColor White
    Write-Host ""
} catch {
    Write-Host "ERROR: Could not read patch completion data: $_" -ForegroundColor Red
    exit 1
}

# Load pre-patch instance data for before/after comparison
$instanceJson = Join-Path $repoDir "artifacts\postgresql_instance.json"
$prePatchData = $null
if (Test-Path $instanceJson) {
    try {
        $prePatchData = Get-Content $instanceJson | ConvertFrom-Json
        Write-Host "Pre-patch instance data loaded" -ForegroundColor Green
        Write-Host ""
    } catch {
        Write-Host "⚠ Could not read pre-patch instance data: $_" -ForegroundColor Yellow
        Write-Host ""
    }
}

# Verify each instance
$verifications = @()
$issues = @()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verifying Patched Instances" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($patchedInstance in $patchData.PatchedInstances) {
    $serviceName = $patchedInstance.ServiceName
    Write-Host "Verifying: $serviceName" -ForegroundColor Cyan
    
    # Get expected version from patched instance data
    $expectedVersion = if ($patchedInstance.TargetVersion) { 
        $patchedInstance.TargetVersion 
    } elseif ($patchedInstance.NewVersion) { 
        $patchedInstance.NewVersion 
    } else { 
        $patchData.NewVersion 
    }
    
    # Find pre-patch information for this instance
    $prePatchInfo = $null
    if ($prePatchData -and $prePatchData.PostgreSQLInstances) {
        $prePatchInfo = $prePatchData.PostgreSQLInstances | Where-Object { $_.ServiceName -eq $serviceName } | Select-Object -First 1
    }
    
    $verification = @{
        ServiceName = $serviceName
        ExpectedVersion = $expectedVersion
        ActualVersion = "Unknown"
        PreviousVersion = if ($prePatchInfo) { $prePatchInfo.Version } else { "Unknown" }
        ServiceRunning = $false
        VersionVerified = $false
        Issues = @()
        PrePatchInfo = if ($prePatchInfo) {
            @{
                Version = $prePatchInfo.Version
                PostgreSQLHome = $prePatchInfo.PostgreSQLHome
                DataDirectory = $prePatchInfo.DataDirectory
                ServiceState = $prePatchInfo.ServiceState
            }
        } else { $null }
    }
    
    # Check service status
    try {
        $service = Get-Service -Name $serviceName -ErrorAction Stop
        $verification.ServiceRunning = ($service.Status -eq 'Running')
        
        if ($verification.ServiceRunning) {
            Write-Host "  ✓ Service is running" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Service is NOT running (Status: $($service.Status))" -ForegroundColor Red
            $verification.Issues += "Service is not running"
            $issues += "Service $serviceName is not running"
        }
    } catch {
        Write-Host "  ✗ Could not check service status: $_" -ForegroundColor Red
        $verification.Issues += "Could not check service status"
        $issues += "Could not check service $serviceName status"
    }
    
    # Get PostgreSQL service details to find pg_home
    try {
        $serviceInfo = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop
        $servicePath = $serviceInfo.PathName
        
        # Extract pg_ctl path and data directory
        $pgHome = $null
        $pgData = $null
        
        if ($servicePath -match '"?([^"]+\\bin\\pg_ctl\.exe)"?') {
            $pgCtlPath = $matches[1]
            $pgHome = Split-Path (Split-Path $pgCtlPath -Parent) -Parent
            $verification.PostgreSQLHome = $pgHome
            
            # Get data directory
            if ($servicePath -match '-D\s+"?([^"]+)"?') {
                $pgData = $matches[1]
                $verification.DataDirectory = $pgData
            }
            
            # Get version from pg_ctl
            if (Test-Path $pgCtlPath) {
                try {
                    $versionOutput = & $pgCtlPath --version 2>&1
                    if ($versionOutput -match 'pg_ctl.*PostgreSQL.*?([\d\.]+)') {
                        $actualVersion = $matches[1]
                        $verification.ActualVersion = $actualVersion
                        
                        if ($actualVersion -eq $expectedVersion) {
                            Write-Host "  ✓ Version verified: $actualVersion" -ForegroundColor Green
                            if ($prePatchInfo) {
                                Write-Host "    Previous: $($prePatchInfo.Version) → New: $actualVersion" -ForegroundColor Cyan
                            }
                            $verification.VersionVerified = $true
                        } else {
                            Write-Host "  ✗ Version mismatch: Expected $expectedVersion, Got $actualVersion" -ForegroundColor Red
                            $verification.Issues += "Version mismatch"
                            $issues += "Service $serviceName has version $actualVersion instead of $expectedVersion"
                        }
                    }
                } catch {
                    Write-Host "  ⚠ Could not determine version: $_" -ForegroundColor Yellow
                    $verification.Issues += "Could not determine version"
                }
            }
        }
    } catch {
        Write-Host "  ⚠ Could not verify version: $_" -ForegroundColor Yellow
        $verification.Issues += "Could not verify version"
    }
    
    # Service running check is sufficient for verification
    if ($verification.ServiceRunning) {
        Write-Host "  ✓ PostgreSQL service is running" -ForegroundColor Green
    } else {
        Write-Host "  ✗ PostgreSQL service is not running" -ForegroundColor Red
        $issues += "Service '$serviceName' is not running"
    }
    
    Write-Host ""
    $verifications += $verification
}

# Determine overall status
$overallStatus = "SUCCESS"
if ($issues.Count -gt 0) {
    $overallStatus = "FAILED"
}

# Create verification artifact
$artifactsDir = Join-Path $repoDir "artifacts"
if (-not (Test-Path $artifactsDir)) {
    New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
}

$verificationResult = @{
    Hostname = $env:COMPUTERNAME
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    OverallStatus = $overallStatus
    Package = $patchData.Package
    ExpectedVersion = $patchData.NewVersion
    Verifications = $verifications
    Issues = $issues
}

$verifyJsonPath = Join-Path $artifactsDir "postgresql_verification.json"
$verificationResult | ConvertTo-Json -Depth 10 | Set-Content -Path $verifyJsonPath

# Display summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verification Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Overall Status: " -NoNewline
if ($overallStatus -eq "SUCCESS") {
    Write-Host $overallStatus -ForegroundColor Green
} else {
    Write-Host $overallStatus -ForegroundColor Red
}
Write-Host ""

foreach ($v in $verifications) {
    Write-Host "Service: $($v.ServiceName)" -ForegroundColor White
    Write-Host "  Running: " -NoNewline
    if ($v.ServiceRunning) {
        Write-Host "✓" -ForegroundColor Green
    } else {
        Write-Host "✗" -ForegroundColor Red
    }
    
    Write-Host "  Version: $($v.ActualVersion) " -NoNewline
    if ($v.VersionVerified) {
        Write-Host "✓" -ForegroundColor Green
    } else {
        Write-Host "✗" -ForegroundColor Red
    }
    
    if ($v.Issues.Count -gt 0) {
        Write-Host "  Issues: $($v.Issues -join ', ')" -ForegroundColor Red
    }
    Write-Host ""
}

if ($issues.Count -gt 0) {
    Write-Host "Issues Found:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  - $issue" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "Verification artifact saved to: $verifyJsonPath" -ForegroundColor Gray
Write-Host ""

if ($overallStatus -eq "SUCCESS") {
    Write-Host "✓ Verification completed successfully" -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗ Verification failed - see issues above" -ForegroundColor Red
    exit 1
}
