<#
.SYNOPSIS
    Check if the server has sufficient disk space for Oracle patching.

.DESCRIPTION
    This script validates that the server has enough free disk space on the Oracle home
    drive to safely perform patching operations. Uses the cpu_RequiredFreeSpace environment
    variable to determine the minimum required space.

.PARAMETER cpu_RequiredFreeSpace
    Required free space in GB (from environment variable)

.EXAMPLE
    .\Check-Disk-Space.ps1
    
.NOTES
    Author: Auto-generated
    Date: November 12, 2025
    Used by GitLab CI/CD pipeline
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Disk Space Validation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get environment variable
$cpu_RequiredFreeSpace = $env:cpu_RequiredFreeSpace

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Required Free Space: $cpu_RequiredFreeSpace GB" -ForegroundColor White
Write-Host ""

# Validate cpu_RequiredFreeSpace is set
if ([string]::IsNullOrWhiteSpace($cpu_RequiredFreeSpace)) {
    Write-Host "ERROR: cpu_RequiredFreeSpace environment variable is required" -ForegroundColor Red
    Write-Host "Please set the required free space in GB (e.g., 20 for 20GB)" -ForegroundColor Red
    exit 1
}

# Convert to number
try {
    $requiredSpaceGB = [decimal]$cpu_RequiredFreeSpace
} catch {
    Write-Host "ERROR: cpu_RequiredFreeSpace must be a valid number" -ForegroundColor Red
    Write-Host "Value provided: $cpu_RequiredFreeSpace" -ForegroundColor Red
    exit 1
}

if ($requiredSpaceGB -le 0) {
    Write-Host "ERROR: cpu_RequiredFreeSpace must be greater than 0" -ForegroundColor Red
    exit 1
}

# Check if oracle_databases.json exists (from check_oracle_installed job)
$oracleJsonPath = "D:\CACI\Config\cpu_Oraclepath\oracle_databases.json"
if (-not (Test-Path $oracleJsonPath)) {
    Write-Host "⚠ No oracle_databases.json found - skipping disk space check" -ForegroundColor Yellow
    Write-Host "Expected at: $oracleJsonPath" -ForegroundColor Yellow
    exit 0
}

# Check for skip markers from previous jobs
$noDatabasesMarker = "D:\CACI\Config\cpu_Oraclepath\no_databases_found.marker"
$sidNotFoundMarker = "D:\CACI\Config\cpu_Oraclepath\sid_not_found.marker"

if (Test-Path $noDatabasesMarker) {
    Write-Host "⚠ No Oracle databases found on server - skipping disk space check" -ForegroundColor Yellow
    exit 0
}

if (Test-Path $sidNotFoundMarker) {
    Write-Host "⚠ SID validation did not find a match - skipping disk space check" -ForegroundColor Yellow
    exit 0
}

# Read Oracle database information
try {
    $oracleData = Get-Content $oracleJsonPath -Raw | ConvertFrom-Json
    
    if (-not $oracleData.RunningDatabases -or $oracleData.RunningDatabases.Count -eq 0) {
        Write-Host "⚠ No running databases in JSON - skipping disk space check" -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "Running Databases:" -ForegroundColor Cyan
    foreach ($db in $oracleData.RunningDatabases) {
        Write-Host "  - SID: $($db.SID), Oracle Home: $($db.OracleHome)" -ForegroundColor White
    }
    Write-Host ""
    
    # Get unique drives from Oracle homes
    $oracleHomeDrives = @()
    foreach ($db in $oracleData.RunningDatabases) {
        if ($db.OracleHome) {
            $drive = Split-Path -Qualifier $db.OracleHome
            if ($drive -and $oracleHomeDrives -notcontains $drive) {
                $oracleHomeDrives += $drive
            }
        }
    }
    
    if ($oracleHomeDrives.Count -eq 0) {
        Write-Host "WARNING: Could not determine Oracle home drives from database information" -ForegroundColor Yellow
        Write-Host "Checking all fixed drives..." -ForegroundColor Yellow
        Write-Host ""
        $oracleHomeDrives = @(Get-PSDrive -PSProvider FileSystem | Where-Object { 
            $_.Root -match '^[A-Z]:\\$' 
        } | Select-Object -ExpandProperty Name | ForEach-Object { "${_}:" })
    }
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Checking Disk Space on Oracle Drives" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $insufficientSpace = @()
    $allDrivesPassed = $true
    
    foreach ($drive in $oracleHomeDrives) {
        Write-Host "Drive: $drive" -ForegroundColor Cyan
        
        try {
            $driveInfo = Get-PSDrive -Name ($drive -replace ':', '') -ErrorAction Stop
            $freeSpaceGB = [math]::Round($driveInfo.Free / 1GB, 2)
            $totalSpaceGB = [math]::Round(($driveInfo.Used + $driveInfo.Free) / 1GB, 2)
            $usedSpaceGB = [math]::Round($driveInfo.Used / 1GB, 2)
            $freePercent = [math]::Round(($freeSpaceGB / $totalSpaceGB) * 100, 2)
            
            Write-Host "  Total Space: $totalSpaceGB GB" -ForegroundColor White
            Write-Host "  Used Space:  $usedSpaceGB GB" -ForegroundColor White
            Write-Host "  Free Space:  $freeSpaceGB GB ($freePercent%)" -ForegroundColor White
            Write-Host "  Required:    $requiredSpaceGB GB" -ForegroundColor White
            Write-Host ""
            
            if ($freeSpaceGB -ge $requiredSpaceGB) {
                Write-Host "  ✓ PASS - Sufficient space available" -ForegroundColor Green
                Write-Host "    Available: $freeSpaceGB GB >= Required: $requiredSpaceGB GB" -ForegroundColor Green
            } else {
                Write-Host "  ✗ FAIL - Insufficient space" -ForegroundColor Red
                Write-Host "    Available: $freeSpaceGB GB < Required: $requiredSpaceGB GB" -ForegroundColor Red
                Write-Host "    Shortfall: $([math]::Round($requiredSpaceGB - $freeSpaceGB, 2)) GB" -ForegroundColor Red
                
                $allDrivesPassed = $false
                $insufficientSpace += @{
                    Drive = $drive
                    FreeSpaceGB = $freeSpaceGB
                    RequiredSpaceGB = $requiredSpaceGB
                    ShortfallGB = [math]::Round($requiredSpaceGB - $freeSpaceGB, 2)
                }
            }
            
        } catch {
            Write-Host "  ⚠ WARNING: Could not check drive $drive - $_" -ForegroundColor Yellow
        }
        
        Write-Host ""
    }
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Disk Space Check Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    if ($allDrivesPassed) {
        Write-Host "✓ All drives have sufficient space for patching" -ForegroundColor Green
        Write-Host "  Required: $requiredSpaceGB GB per drive" -ForegroundColor White
        Write-Host "  Drives checked: $($oracleHomeDrives -join ', ')" -ForegroundColor White
        Write-Host ""
        Write-Host "✓ Proceeding with patch job..." -ForegroundColor Green
        exit 0
    } else {
        Write-Host "✗ INSUFFICIENT DISK SPACE DETECTED" -ForegroundColor Red
        Write-Host ""
        Write-Host "The following drives do not have enough free space:" -ForegroundColor Red
        foreach ($drive in $insufficientSpace) {
            Write-Host "  Drive: $($drive.Drive)" -ForegroundColor Red
            Write-Host "    Free Space: $($drive.FreeSpaceGB) GB" -ForegroundColor Red
            Write-Host "    Required:   $($drive.RequiredSpaceGB) GB" -ForegroundColor Red
            Write-Host "    Shortfall:  $($drive.ShortfallGB) GB" -ForegroundColor Red
            Write-Host ""
        }
        Write-Host "Action Required:" -ForegroundColor Yellow
        Write-Host "  1. Free up disk space on the affected drives" -ForegroundColor Yellow
        Write-Host "  2. Or reduce the cpu_RequiredFreeSpace variable if appropriate" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "✗ PATCH JOB WILL NOT RUN - Insufficient disk space" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "ERROR: Failed to check disk space: $_" -ForegroundColor Red
    exit 1
}
