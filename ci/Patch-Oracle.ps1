<#
.SYNOPSIS
    Execute Oracle database patching process.

.DESCRIPTION
    This script validates environment variables and executes the Oracle database patching.
    Requires cpu_PatchDB and cpu_SID environment variables to be set.

.PARAMETER cpu_PatchDB
    The Oracle patch to apply (from environment variable)

.PARAMETER cpu_SID
    The Oracle SID to patch (from environment variable)

.EXAMPLE
    .\Patch-Oracle.ps1
    
.NOTES
    Author: Auto-generated
    Date: November 12, 2025
    Used by GitLab CI/CD pipeline
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Oracle Database Patching" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get environment variables
$cpu_PatchDB = $env:cpu_PatchDB
$cpu_SID = $env:cpu_SID

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  cpu_SID = $cpu_SID"
Write-Host ""

# Check if oracle_databases.json exists (from previous job)
$oracleJsonPath = Join-Path $PSScriptRoot "..\artifacts\oracle_databases.json"
if (-not (Test-Path $oracleJsonPath)) {
    Write-Host "⚠ No Oracle databases detected - skipping patch" -ForegroundColor Yellow
    Write-Host "Expected to find: $oracleJsonPath" -ForegroundColor Yellow
    exit 0
}

Write-Host "✓ Oracle databases detected at: $oracleJsonPath" -ForegroundColor Green

# Display detected databases
try {
    $oracleData = Get-Content $oracleJsonPath | ConvertFrom-Json
    Write-Host ""
    Write-Host "Detected Oracle Databases:" -ForegroundColor Cyan
    foreach ($db in $oracleData.RunningDatabases) {
        Write-Host "  - SID: $($db.SID), Oracle Home: $($db.OracleHome)" -ForegroundColor White
    }
    Write-Host ""
} catch {
    Write-Host "⚠ Could not read oracle_databases.json: $_" -ForegroundColor Yellow
}

# Validate required environment variables
$validationFailed = $false

if ([string]::IsNullOrWhiteSpace($cpu_SID)) {
    Write-Host "ERROR: cpu_SID environment variable is required for Patch Oracle action" -ForegroundColor Red
    $validationFailed = $true
}

if ($validationFailed) {
    Write-Host ""
    Write-Host "Please set the required environment variables and try again." -ForegroundColor Red
    exit 1
}

Write-Host "✓ All required environment variables are set" -ForegroundColor Green
Write-Host ""

# Check if database version already matches the patch version
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Pre-Patch Version Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

try {
    # Read pack_oracle_dbhome.xml from the local package folder (Artifactory no longer used)
    $packageFolder = Join-Path $installerRoot "package"
    $tempPackXml = Join-Path $packageFolder "pack_oracle_dbhome.xml"
    
    Write-Host "Reading pack metadata from: $tempPackXml" -ForegroundColor Cyan
    
    if (-not (Test-Path $tempPackXml)) {
        Write-Host "⚠ WARNING: pack_oracle_dbhome.xml not found in package folder" -ForegroundColor Yellow
        Write-Host "Skipping pre-patch version check" -ForegroundColor Yellow
    } else {
        Write-Host "✓ Pack metadata found" -ForegroundColor Green
        Write-Host ""
        
        # Parse XML to get version
        [xml]$packXml = Get-Content $tempPackXml
        $packVersion = $packXml.Objs.Obj.MS.S | Where-Object { $_.N -eq 'version' } | Select-Object -ExpandProperty '#text'
        
        if ([string]::IsNullOrWhiteSpace($packVersion)) {
            Write-Host "⚠ WARNING: Could not parse version from pack_oracle_dbhome.xml" -ForegroundColor Yellow
            Write-Host "Skipping pre-patch version check" -ForegroundColor Yellow
        } else {
            Write-Host "Pack Version: $packVersion" -ForegroundColor White
            Write-Host ""
            
            # Find the database matching the SID
            $targetDb = $oracleData.RunningDatabases | Where-Object { $_.SID -eq $cpu_SID }
            
            if (-not $targetDb) {
                Write-Host "⚠ WARNING: Could not find database with SID $cpu_SID" -ForegroundColor Yellow
                Write-Host "Skipping pre-patch version check" -ForegroundColor Yellow
            } else {
                $oracleHome = $targetDb.OracleHome
                
                # Set Oracle environment
                $env:ORACLE_HOME = $oracleHome
                $env:ORACLE_SID = $cpu_SID
                $sqlplusPath = Join-Path $oracleHome "bin\sqlplus.exe"
                
                if (-not (Test-Path $sqlplusPath)) {
                    Write-Host "⚠ WARNING: sqlplus.exe not found at $sqlplusPath" -ForegroundColor Yellow
                    Write-Host "Skipping pre-patch version check" -ForegroundColor Yellow
                } else {
                    Write-Host "Querying dba_registry for current version_full..." -ForegroundColor Cyan
                    
                    # Create SQL script to query version_full from dba_registry (excluding APEX)
                    $sqlScript = @"
SET PAGESIZE 0
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

SELECT DISTINCT version_full 
FROM dba_registry 
WHERE comp_name NOT LIKE '%Application Express%'
ORDER BY version_full;

EXIT;
"@
                    
                    $tempSqlFile = Join-Path $env:TEMP "prepatch_version_check_$($cpu_SID).sql"
                    $sqlScript | Out-File -FilePath $tempSqlFile -Encoding ASCII -Force
                    
                    try {
                        # Execute SQL query
                        $sqlOutput = & $sqlplusPath -S "/ as sysdba" "@$tempSqlFile" 2>&1
                        
                        # Clean up temp file
                        Remove-Item $tempSqlFile -Force -ErrorAction SilentlyContinue
                        
                        # Parse output to get versions
                        $dbVersions = @()
                        foreach ($line in $sqlOutput) {
                            $line = $line.Trim()
                            if (-not [string]::IsNullOrWhiteSpace($line) -and $line -match '^\d+\.\d+\.\d+') {
                                $dbVersions += $line
                            }
                        }
                        
                        if ($dbVersions.Count -eq 0) {
                            Write-Host "⚠ WARNING: Could not retrieve version from dba_registry" -ForegroundColor Yellow
                            Write-Host "SQL Output: $($sqlOutput -join ', ')" -ForegroundColor Gray
                            Write-Host "Skipping pre-patch version check" -ForegroundColor Yellow
                        } else {
                            Write-Host "Current Database Version(s) (excluding APEX):" -ForegroundColor Cyan
                            
                            $allVersionsMatch = $true
                            foreach ($dbVersion in $dbVersions) {
                                # Extract first 3 parts of version (e.g., 19.21.0.0.0 -> 19.21.0)
                                if ($dbVersion -match '^(\d+\.\d+\.\d+)') {
                                    $dbVersion3Part = $matches[1]
                                } else {
                                    $dbVersion3Part = $dbVersion
                                }
                                
                                $versionMatch = $dbVersion3Part -eq $packVersion
                                $statusColor = if ($versionMatch) { "Green" } else { "Yellow" }
                                $statusIcon = if ($versionMatch) { "✓" } else { "⚠" }
                                
                                Write-Host "  $statusIcon $dbVersion3Part" -ForegroundColor $statusColor
                                
                                if (-not $versionMatch) {
                                    $allVersionsMatch = $false
                                }
                            }
                            
                            Write-Host ""
                            
                            if ($allVersionsMatch) {
                                Write-Host "========================================" -ForegroundColor Green
                                Write-Host "✓ DATABASE ALREADY AT TARGET VERSION" -ForegroundColor Green
                                Write-Host "========================================" -ForegroundColor Green
                                Write-Host ""
                                Write-Host "The database is already running version $packVersion" -ForegroundColor Green
                                Write-Host "No patching is required - skipping patch execution" -ForegroundColor Green
                                Write-Host ""
                                Write-Host "This is not an error - the job completed successfully" -ForegroundColor Cyan
                                Write-Host "because the database is already at the target version." -ForegroundColor Cyan
                                Write-Host ""
                                
                                exit 0
                            } else {
                                Write-Host "Database version differs from pack version - proceeding with patch" -ForegroundColor Cyan
                            }
                        }
                        
                    } catch {
                        Write-Host "⚠ WARNING: Error querying database: $($_.Exception.Message)" -ForegroundColor Yellow
                        Write-Host "Skipping pre-patch version check" -ForegroundColor Yellow
                        # Clean up temp file
                        Remove-Item $tempSqlFile -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        
        # No cleanup needed - pack_oracle_dbhome.xml is a persistent local package file
    }
    
} catch {
    Write-Host "⚠ WARNING: Failed pre-patch version check: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "Proceeding with patch anyway" -ForegroundColor Yellow
}

Write-Host ""

# Navigate to the installer root directory
$installerRoot = Split-Path -Parent $PSScriptRoot
Set-Location $installerRoot

# Locate patch files in the local package folder
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Locating Oracle Patch Files" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Package files (database pack + pack_oracle_dbhome.xml metadata) are expected to be
# pre-placed in the repo's package/ folder (Artifactory no longer used)
$packageFolder = Join-Path $installerRoot "package"
if (-not (Test-Path $packageFolder)) {
    Write-Host "Creating package folder: $packageFolder" -ForegroundColor Cyan
    New-Item -Path $packageFolder -ItemType Directory -Force | Out-Null
}

Write-Host "Package folder: $packageFolder" -ForegroundColor White
Write-Host ""

$existingFiles = Get-ChildItem -Path $packageFolder -File -ErrorAction SilentlyContinue
if (-not $existingFiles -or $existingFiles.Count -eq 0) {
    Write-Host "ERROR: No patch files found in: $packageFolder" -ForegroundColor Red
    Write-Host "Place the Oracle database pack (zip) and pack_oracle_dbhome.xml in that folder." -ForegroundColor Red
    exit 1
}

Write-Host "✓ Found $($existingFiles.Count) file(s) in package folder" -ForegroundColor Green
foreach ($file in $existingFiles) {
    Write-Host "  - $($file.Name)" -ForegroundColor White
}
Write-Host ""

if (-not (Test-Path (Join-Path $packageFolder "pack_oracle_dbhome.xml"))) {
    Write-Host "⚠ Warning: pack_oracle_dbhome.xml not found - version validation steps will be skipped" -ForegroundColor Yellow
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Executing Patch_database.bat" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Execute the patch script with database SID parameter
$patchScript = Join-Path $installerRoot "Patch_database.bat"

if (-not (Test-Path $patchScript)) {
    Write-Host "ERROR: Patch_database.bat not found at: $patchScript" -ForegroundColor Red
    exit 1
}

try {
    Write-Host "Calling: $patchScript $cpu_SID" -ForegroundColor Cyan
    
    # Execute batch file and capture output
    $process = Start-Process -FilePath $patchScript -ArgumentList $cpu_SID -NoNewWindow -Wait -PassThru
    $exitCode = $process.ExitCode
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Check for error keywords in addition to exit code
    if ($exitCode -eq 0) {
        Write-Host "✓ Oracle patch completed successfully" -ForegroundColor Green
    } else {
        Write-Host "✗ Oracle patch failed with exit code: $exitCode" -ForegroundColor Red
    }
    
    Write-Host "========================================" -ForegroundColor Cyan
    exit $exitCode
} catch {
    Write-Host "ERROR: Failed to execute patch script: $_" -ForegroundColor Red
    exit 1
}
