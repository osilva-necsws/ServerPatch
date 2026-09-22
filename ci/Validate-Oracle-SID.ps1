<#
.SYNOPSIS
    Validate that the specified Oracle SID exists in the detected databases.

.DESCRIPTION
    This script checks if the cpu_SID environment variable matches one of the running
    Oracle database instances detected by the check_oracle_installed job.

.PARAMETER cpu_SID
    The Oracle SID to validate (from environment variable)

.EXAMPLE
    .\Validate-Oracle-SID.ps1
    
.NOTES
    Author: Auto-generated
    Date: November 12, 2025
    Used by GitLab CI/CD pipeline
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Oracle SID Validation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get environment variables
$cpu_SID = $env:cpu_SID
$cpu_PatchDB = $env:cpu_PatchDB

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  cpu_SID = $cpu_SID"
Write-Host "  cpu_PatchDB = $cpu_PatchDB"
Write-Host ""

# Validate cpu_SID is set
if ([string]::IsNullOrWhiteSpace($cpu_SID)) {
    Write-Host "ERROR: cpu_SID environment variable is required" -ForegroundColor Red
    Write-Host "Please set the cpu_SID variable and try again." -ForegroundColor Red
    exit 1
}

# Validate cpu_PatchDB is set
if ([string]::IsNullOrWhiteSpace($cpu_PatchDB)) {
    Write-Host "ERROR: cpu_PatchDB environment variable is required" -ForegroundColor Red
    Write-Host "Please set the cpu_PatchDB variable and try again." -ForegroundColor Red
    exit 1
}

# Check if oracle_databases.json exists (from check_oracle_installed job)
$oracleJsonPath = Join-Path $PSScriptRoot "..\artifacts\oracle_databases.json"
if (-not (Test-Path $oracleJsonPath)) {
    Write-Host "ERROR: oracle_databases.json not found at: $oracleJsonPath" -ForegroundColor Red
    Write-Host "The check_oracle_installed job must run successfully before this job." -ForegroundColor Red
    exit 1
}

Write-Host "✓ Oracle databases file found: $oracleJsonPath" -ForegroundColor Green
Write-Host ""

# Read and parse JSON
try {
    $oracleData = Get-Content $oracleJsonPath -Raw | ConvertFrom-Json
    
    if (-not $oracleData.RunningDatabases -or $oracleData.RunningDatabases.Count -eq 0) {
        Write-Host "ERROR: No running databases found in oracle_databases.json" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Detected Running Databases:" -ForegroundColor Cyan
    foreach ($db in $oracleData.RunningDatabases) {
        Write-Host "  - SID: $($db.SID), Oracle Home: $($db.OracleHome), Status: $($db.Status)" -ForegroundColor White
    }
    Write-Host ""
    
    # Check if cpu_SID matches any running database
    $matchFound = $false
    $matchedDb = $null
    foreach ($db in $oracleData.RunningDatabases) {
        if ($db.SID -eq $cpu_SID) {
            $matchFound = $true
            $matchedDb = $db
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "✓ MATCH FOUND" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "The specified SID '$cpu_SID' matches a running Oracle database:" -ForegroundColor Green
            Write-Host "  SID: $($db.SID)" -ForegroundColor White
            Write-Host "  Service: $($db.ServiceName)" -ForegroundColor White
            Write-Host "  Oracle Home: $($db.OracleHome)" -ForegroundColor White
            Write-Host "  Status: $($db.Status)" -ForegroundColor White
            Write-Host "  StartType: $($db.StartType)" -ForegroundColor White
            Write-Host ""
            break
        }
    }
    
    # If match found, validate Oracle version against patch package
    if ($matchFound) {
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Validating Oracle Version" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        
        # Download pack_oracle_dbhome.xml from Artifactory
        try {
            $artifactoryUrl = $cpu_PatchDB.TrimEnd('/') + '/'
            $packXmlUrl = $artifactoryUrl + 'pack_oracle_dbhome.xml'
            $tempPackXml = Join-Path $env:TEMP "pack_oracle_dbhome_$([guid]::NewGuid()).xml"
            
            Write-Host "Downloading pack metadata from: $packXmlUrl" -ForegroundColor Cyan
            Invoke-WebRequest -Uri $packXmlUrl -OutFile $tempPackXml -UseBasicParsing
            
            if (-not (Test-Path $tempPackXml)) {
                Write-Host "⚠ WARNING: Could not download pack_oracle_dbhome.xml" -ForegroundColor Yellow
                Write-Host "Skipping version validation" -ForegroundColor Yellow
            } else {
                Write-Host "✓ Pack metadata downloaded" -ForegroundColor Green
                Write-Host ""
                
                # Parse XML to get version
                [xml]$packXml = Get-Content $tempPackXml
                $packVersion = $packXml.Objs.Obj.MS.S | Where-Object { $_.N -eq 'version' } | Select-Object -ExpandProperty '#text'
                
                if ([string]::IsNullOrWhiteSpace($packVersion)) {
                    Write-Host "⚠ WARNING: Could not parse version from pack_oracle_dbhome.xml" -ForegroundColor Yellow
                    Write-Host "Skipping version validation" -ForegroundColor Yellow
                } else {
                    Write-Host "Pack Version: $packVersion" -ForegroundColor White
                    Write-Host ""
                    
                    # Get current Oracle version from dba_registry
                    $oracleHome = $matchedDb.OracleHome
                    
                    if ([string]::IsNullOrWhiteSpace($oracleHome)) {
                        Write-Host "⚠ WARNING: Oracle Home not detected for SID $cpu_SID" -ForegroundColor Yellow
                        Write-Host "Skipping version validation" -ForegroundColor Yellow
                    } else {
                        Write-Host "Oracle Home: $oracleHome" -ForegroundColor White
                        
                        # Set Oracle environment
                        $env:ORACLE_HOME = $oracleHome
                        $env:ORACLE_SID = $cpu_SID
                        $sqlplusPath = Join-Path $oracleHome "bin\sqlplus.exe"
                        
                        if (-not (Test-Path $sqlplusPath)) {
                            Write-Host "⚠ WARNING: sqlplus.exe not found at $sqlplusPath" -ForegroundColor Yellow
                            Write-Host "Skipping version validation" -ForegroundColor Yellow
                        } else {
                            Write-Host "Querying dba_registry for version_full..." -ForegroundColor Cyan
                            
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
                            
                            $tempSqlFile = Join-Path $env:TEMP "version_check_$($cpu_SID).sql"
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
                                    Write-Host "Skipping version validation" -ForegroundColor Yellow
                                } else {
                                    Write-Host "Current Database Versions (excluding APEX):" -ForegroundColor Cyan
                                    
                                    $versionMismatch = $false
                                    $mismatchedVersions = @()
                                    
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
                                            $versionMismatch = $true
                                            $mismatchedVersions += $dbVersion3Part
                                        }
                                    }
                                    
                                    Write-Host ""
                                    
                                    if ($versionMismatch) {
                                        Write-Host "⚠ WARNING: Database components do not match patch pack version" -ForegroundColor Yellow
                                        Write-Host "  Expected (pack):  $packVersion" -ForegroundColor Yellow
                                        Write-Host "  Mismatched:       $($mismatchedVersions -join ', ')" -ForegroundColor Yellow
                                        Write-Host ""
                                        Write-Host "This patch will upgrade/downgrade the database components." -ForegroundColor Yellow
                                        Write-Host "Proceeding with caution..." -ForegroundColor Yellow
                                        Write-Host ""
                                        Write-Host "##vso[task.complete result=SucceededWithIssues;]Version mismatch detected"
                                        Write-Warning "Version mismatch (excluding APEX): Expected=$packVersion, Found=$($mismatchedVersions -join ', ')"
                                    } else {
                                        Write-Host "✓ All database components match patch pack version" -ForegroundColor Green
                                        Write-Host "  Version: $packVersion" -ForegroundColor Green
                                    }
                                }
                                
                            } catch {
                                Write-Host "⚠ WARNING: Error querying database: $($_.Exception.Message)" -ForegroundColor Yellow
                                Write-Host "Skipping version validation" -ForegroundColor Yellow
                                # Clean up temp file
                                Remove-Item $tempSqlFile -Force -ErrorAction SilentlyContinue
                            }
                        }
                    }
                }
                
                # Clean up temp file
                Remove-Item $tempPackXml -Force -ErrorAction SilentlyContinue
            }
            
        } catch {
            Write-Host "⚠ WARNING: Failed to validate version: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "Skipping version validation" -ForegroundColor Yellow
        }
        
        Write-Host ""
        Write-Host "✓ Proceeding with patch jobs..." -ForegroundColor Green
    }
    
    if (-not $matchFound) {
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "⚠ NO MATCH FOUND" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "The specified SID '$cpu_SID' was NOT found in the running databases." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Available SIDs:" -ForegroundColor Yellow
        foreach ($db in $oracleData.RunningDatabases) {
            Write-Host "  - $($db.SID)" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "⚠ Skipping remaining patch jobs - no matching database found." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "This is not an error - the pipeline will complete successfully," -ForegroundColor Cyan
        Write-Host "but patch jobs will be skipped because the specified SID does not exist." -ForegroundColor Cyan
        
        # Create marker files to signal no match found (workspace and shared)
        $workspaceMarkerPath = Join-Path $PSScriptRoot "..\artifacts\sid_not_found.marker"
        $sharedMarkerPath = "D:\CACI\Config\cpu_Oraclepath\sid_not_found.marker"
        
        "SID_NOT_FOUND: $cpu_SID" | Out-File -FilePath $workspaceMarkerPath -Force
        "SID_NOT_FOUND: $cpu_SID" | Out-File -FilePath $sharedMarkerPath -Force
        Write-Host ""
        Write-Host "Created marker files:" -ForegroundColor Cyan
        Write-Host "  - $workspaceMarkerPath" -ForegroundColor Cyan
        Write-Host "  - $sharedMarkerPath" -ForegroundColor Cyan
        
        # Exit successfully to allow pipeline to continue gracefully
        exit 0
    }
    
    # If match found, ensure no marker files exist
    $workspaceMarkerPath = Join-Path $PSScriptRoot "..\artifacts\sid_not_found.marker"
    $sharedMarkerPath = "D:\CACI\Config\cpu_Oraclepath\sid_not_found.marker"
    
    if (Test-Path $workspaceMarkerPath) {
        Remove-Item $workspaceMarkerPath -Force
    }
    if (Test-Path $sharedMarkerPath) {
        Remove-Item $sharedMarkerPath -Force
    }
    
    exit 0
    
} catch {
    Write-Host "ERROR: Failed to parse oracle_databases.json: $_" -ForegroundColor Red
    exit 1
}
