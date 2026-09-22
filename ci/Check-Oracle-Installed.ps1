<#
.SYNOPSIS
    Check if Oracle databases are installed and running on the server.

.DESCRIPTION
    This script runs the Oracle database detection and determines if patch jobs should proceed.
    Exits with code 0 if databases are found, allowing dependent jobs to run.
    Exits with code 0 even if no databases found, but signals through output.

.EXAMPLE
    .\Check-Oracle-Installed.ps1
    
.NOTES
    Author: Auto-generated
    Date: November 12, 2025
    Used by GitLab CI/CD pipeline
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Checking for Oracle Database Installations" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$scriptPath = Join-Path $PSScriptRoot "Check-OracleDatabases.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Host "ERROR: Check-OracleDatabases.ps1 not found at: $scriptPath" -ForegroundColor Red
    exit 1
}

try {
    Write-Host "Running Oracle database detection script..." -ForegroundColor Cyan
    & $scriptPath
    $exitCode = $LASTEXITCODE
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    
    if ($exitCode -eq 0) {
        Write-Host "✓ Oracle databases found - proceeding with patch jobs" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
        
        # Remove marker file if it exists from previous runs (both locations)
        $workspaceMarkerPath = Join-Path $PSScriptRoot "..\artifacts\no_databases_found.marker"
        $sharedMarkerPath = "D:\CACI\Config\cpu_Oraclepath\no_databases_found.marker"
        
        if (Test-Path $workspaceMarkerPath) {
            Remove-Item $workspaceMarkerPath -Force
        }
        if (Test-Path $sharedMarkerPath) {
            Remove-Item $sharedMarkerPath -Force
        }
        
        exit 0
    } else {
        Write-Host "⚠ No running Oracle databases found - skipping patch jobs" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "This is not an error - the pipeline will complete successfully," -ForegroundColor Cyan
        Write-Host "but all patch-related jobs will be skipped because no databases were detected." -ForegroundColor Cyan
        
        # Create marker files to signal no databases found (both locations)
        $workspaceMarkerPath = Join-Path $PSScriptRoot "..\artifacts\no_databases_found.marker"
        $sharedMarkerPath = "D:\CACI\Config\cpu_Oraclepath\no_databases_found.marker"
        
        # Create workspace artifacts directory if needed
        $workspaceArtifactsDir = Split-Path $workspaceMarkerPath -Parent
        if (-not (Test-Path $workspaceArtifactsDir)) {
            New-Item -Path $workspaceArtifactsDir -ItemType Directory -Force | Out-Null
        }
        
        # Create shared config directory if needed
        $sharedMarkerDir = Split-Path $sharedMarkerPath -Parent
        if (-not (Test-Path $sharedMarkerDir)) {
            New-Item -Path $sharedMarkerDir -ItemType Directory -Force | Out-Null
        }
        
        # Write marker files
        "NO_DATABASES_FOUND" | Out-File -FilePath $workspaceMarkerPath -Force
        "NO_DATABASES_FOUND" | Out-File -FilePath $sharedMarkerPath -Force
        
        Write-Host ""
        Write-Host "Created marker files:" -ForegroundColor Cyan
        Write-Host "  - $workspaceMarkerPath" -ForegroundColor Cyan
        Write-Host "  - $sharedMarkerPath" -ForegroundColor Cyan
        
        # Still exit 0 to allow pipeline to continue gracefully
        exit 0
    }
} catch {
    Write-Host "ERROR: Failed to run Oracle check script: $_" -ForegroundColor Red
    exit 1
}
