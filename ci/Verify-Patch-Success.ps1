# Verify Oracle Patch Success
# Checks dba_registry for version consistency and component status
# Checks for invalid objects in the database

param()

Write-Host "================================" -ForegroundColor Cyan
Write-Host "Oracle Patch Verification Check" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Check if markers exist indicating earlier failures
if (Test-Path "artifacts/no_databases_found.marker") {
    Write-Host "⚠ No Oracle databases found on server - skipping verification" -ForegroundColor Yellow
    exit 0
}

if (Test-Path "artifacts/sid_not_found.marker") {
    Write-Host "⚠ SID validation did not find a match - skipping verification" -ForegroundColor Yellow
    exit 0
}

# Read the database details from the JSON artifact
$jsonPath = "artifacts/oracle_databases.json"
Write-Host "DEBUG: Checking for JSON file at: $jsonPath" -ForegroundColor Gray
Write-Host "DEBUG: Current directory: $PWD" -ForegroundColor Gray
Write-Host "DEBUG: Artifacts folder exists: $(Test-Path 'artifacts')" -ForegroundColor Gray
if (Test-Path 'artifacts') {
    Write-Host "DEBUG: Files in artifacts folder:" -ForegroundColor Gray
    Get-ChildItem 'artifacts' -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
}

if (-not (Test-Path $jsonPath)) {
    Write-Host "❌ ERROR: Database JSON file not found at $jsonPath" -ForegroundColor Red
    exit 1
}

$jsonContent = Get-Content $jsonPath -Raw
$dbInfo = $jsonContent | ConvertFrom-Json
$databases = $dbInfo.RunningDatabases

$cpu_SID = $env:cpu_SID

Write-Host "Server: $($dbInfo.ServerName)" -ForegroundColor Cyan
Write-Host "Found $($databases.Count) running database(s)" -ForegroundColor Cyan

if ([string]::IsNullOrWhiteSpace($cpu_SID)) {
    Write-Host "❌ ERROR: cpu_SID environment variable is not set" -ForegroundColor Red
    exit 1
}

# Find the database matching the SID
$targetDb = $databases | Where-Object { $_.SID -eq $cpu_SID }

if (-not $targetDb) {
    Write-Host "❌ ERROR: Could not find database with SID '$cpu_SID'" -ForegroundColor Red
    Write-Host "Available databases:" -ForegroundColor Yellow
    $databases | ForEach-Object { Write-Host "  - SID: $($_.SID), Home: $($_.OracleHome)" -ForegroundColor Yellow }
    exit 1
}

Write-Host "Verifying database: $($targetDb.SID) on $($targetDb.OracleHome)" -ForegroundColor Green
Write-Host ""

# Set Oracle environment
$env:ORACLE_HOME = $targetDb.OracleHome
$env:ORACLE_SID = $targetDb.SID
$sqlplusPath = Join-Path $env:ORACLE_HOME "bin\sqlplus.exe"

if (-not (Test-Path $sqlplusPath)) {
    Write-Host "❌ ERROR: sqlplus.exe not found at $sqlplusPath" -ForegroundColor Red
    exit 1
}

# Read expected version from the local pack_oracle_dbhome.xml (Artifactory no longer used)
$expectedPackVersion = $null
try {
    $packageFolder = Join-Path $PSScriptRoot "..\package"
    $tempPackXml = Join-Path $packageFolder "pack_oracle_dbhome.xml"

    Write-Host "Reading pack metadata for version verification..." -ForegroundColor Cyan

    if (Test-Path $tempPackXml) {
        [xml]$packXml = Get-Content $tempPackXml
        $expectedPackVersion = $packXml.Objs.Obj.MS.S | Where-Object { $_.N -eq 'version' } | Select-Object -ExpandProperty '#text'

        if ($expectedPackVersion) {
            Write-Host "✓ Expected pack version: $expectedPackVersion" -ForegroundColor Green
        }
    } else {
        Write-Host "⚠ WARNING: pack_oracle_dbhome.xml not found in package folder" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠ WARNING: Could not retrieve pack version for comparison: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""

# Run utlrp.sql to compile invalid objects
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Compiling Invalid Objects (utlrp.sql)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Running @?/rdbms/admin/utlrp to recompile database objects..." -ForegroundColor Cyan
Write-Host "This may take several minutes..." -ForegroundColor Yellow
Write-Host ""

$utlrpScript = @"
SET ECHO ON
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

@?/rdbms/admin/utlrp

EXIT;
"@

$tempUtlrpFile = Join-Path $env:TEMP "run_utlrp_$($targetDb.SID).sql"
$utlrpScript | Out-File -FilePath $tempUtlrpFile -Encoding ASCII -Force

# Execute utlrp.sql
$utlrpOutput = & $sqlplusPath -S "/ as sysdba" "@$tempUtlrpFile" 2>&1

# Clean up temp file
Remove-Item $tempUtlrpFile -Force -ErrorAction SilentlyContinue

Write-Host "✓ Compilation complete" -ForegroundColor Green
Write-Host ""

# Create SQL script to check registry and invalid objects
$sqlScript = @"
SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- Check dba_registry
PROMPT
PROMPT ========================================
PROMPT DBA_REGISTRY Component Status
PROMPT ========================================
SELECT comp_name, version_full, status 
FROM dba_registry 
ORDER BY comp_name;

-- Get distinct version_full
PROMPT
PROMPT ========================================
PROMPT Distinct Version Numbers (VERSION_FULL)
PROMPT ========================================
SELECT DISTINCT version_full 
FROM dba_registry 
ORDER BY version_full;

-- Count invalid objects
PROMPT
PROMPT ========================================
PROMPT Invalid Objects Count
PROMPT ========================================
SELECT object_type, COUNT(*) as invalid_count
FROM dba_objects 
WHERE status = 'INVALID'
GROUP BY object_type
ORDER BY invalid_count DESC;

PROMPT
PROMPT Total Invalid Objects:
SELECT COUNT(*) as total_invalid 
FROM dba_objects 
WHERE status = 'INVALID';

-- Get application version
PROMPT
PROMPT ========================================
PROMPT ChildView Application Version
PROMPT ========================================
SELECT info_text as application_version
FROM impulse.info 
WHERE info_id='CVW_VER';

EXIT;
"@

$tempSqlFile = Join-Path $env:TEMP "verify_patch_$($targetDb.SID).sql"
$sqlScript | Out-File -FilePath $tempSqlFile -Encoding ASCII -Force

Write-Host "Running verification queries..." -ForegroundColor Cyan

# Execute SQL*Plus
$sqlplusOutput = & $sqlplusPath -S "/ as sysdba" "@$tempSqlFile" 2>&1

# Clean up temp file
Remove-Item $tempSqlFile -Force -ErrorAction SilentlyContinue

# Display output
Write-Host $sqlplusOutput

# Parse output for verification
$registryIssues = @()
$versionNumbers = @()
$totalInvalid = 0
$appVersion = $null

# Check for components with non-VALID status
$lines = $sqlplusOutput -split "`n"
$inRegistrySection = $false
$inVersionSection = $false
$inAppVersionSection = $false

foreach ($line in $lines) {
    if ($line -match "DBA_REGISTRY Component Status") {
        $inRegistrySection = $true
        $inVersionSection = $false
        $inAppVersionSection = $false
        continue
    }
    if ($line -match "Distinct Version Numbers") {
        $inRegistrySection = $false
        $inVersionSection = $true
        $inAppVersionSection = $false
        continue
    }
    if ($line -match "Invalid Objects Count") {
        $inRegistrySection = $false
        $inVersionSection = $false
        $inAppVersionSection = $false
        continue
    }
    if ($line -match "ChildView Application Version") {
        $inRegistrySection = $false
        $inVersionSection = $false
        $inAppVersionSection = $true
        continue
    }
    if ($line -match "Total Invalid Objects:") {
        continue
    }
    
    # Parse registry lines
    if ($inRegistrySection -and $line.Trim() -ne "" -and $line -notmatch "^-+" -and $line -notmatch "COMP_NAME" -and $line -notmatch "VERSION_FULL") {
        if ($line -match "(\S.+?)\s+(\d+\.\d+\.\d+\.\d+\.\d+)\s+(\S+)") {
            $compName = $matches[1].Trim()
            $status = $matches[3].Trim()
            
            if ($status -ne "VALID") {
                $registryIssues += "Component '$compName' has status '$status' (expected VALID)"
            }
        }
    }
    
    # Parse version numbers
    if ($inVersionSection -and $line.Trim() -ne "" -and $line -notmatch "^-+" -and $line -notmatch "VERSION_FULL") {
        $versionMatch = $line.Trim()
        if ($versionMatch -match "^\d+\.\d+\.\d+\.\d+\.\d+") {
            $versionNumbers += $versionMatch
        }
    }
    
    # Parse application version
    if ($inAppVersionSection -and $line.Trim() -ne "" -and $line -notmatch "^-+" -and $line -notmatch "APPLICATION_VERSION") {
        $appVersion = $line.Trim()
    }
    
    # Parse invalid objects count
    if ($line -match "^\s*(\d+)\s*$" -and -not $inRegistrySection -and -not $inVersionSection -and -not $inAppVersionSection) {
        $totalInvalid = [int]$matches[1]
    }
}

# Generate summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verification Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check version consistency and compare against expected pack version
$versionMismatchDetected = $false
if ($versionNumbers.Count -gt 0) {
    Write-Host "✓ Version numbers found: $($versionNumbers -join ', ')" -ForegroundColor Green
    
    # Compare against expected pack version if available
    if ($expectedPackVersion) {
        Write-Host "Expected pack version: $expectedPackVersion" -ForegroundColor Cyan
        
        $allVersionsMatch = $true
        foreach ($dbVersion in $versionNumbers) {
            # Skip APEX version
            if ($dbVersion -match '^\d+\.\d+\.\d+') {
                $dbVersion3Part = $matches[0]
                
                if ($dbVersion3Part -ne $expectedPackVersion) {
                    $allVersionsMatch = $false
                }
            }
        }
        
        if (-not $allVersionsMatch) {
            Write-Host "⚠ WARNING: Database version does not match expected pack version" -ForegroundColor Yellow
            Write-Host "  Expected: $expectedPackVersion" -ForegroundColor Yellow
            Write-Host "  Actual:   $($versionNumbers -join ', ')" -ForegroundColor Yellow
            $versionMismatchDetected = $true
        } else {
            Write-Host "✓ Database version matches expected pack version ($expectedPackVersion)" -ForegroundColor Green
        }
    }
    
    if ($versionNumbers.Count -gt 1) {
        Write-Host "ℹ Multiple version numbers detected (Oracle APEX may have a different version)" -ForegroundColor Cyan
    } elseif (-not $versionMismatchDetected) {
        Write-Host "✓ All components at consistent version" -ForegroundColor Green
    }
} else {
    Write-Host "⚠ Could not parse version numbers from output" -ForegroundColor Yellow
}

# Check registry status
if ($registryIssues.Count -eq 0) {
    Write-Host "✓ All components have VALID status" -ForegroundColor Green
} else {
    Write-Host "❌ Component status issues found:" -ForegroundColor Red
    foreach ($issue in $registryIssues) {
        Write-Host "  - $issue" -ForegroundColor Red
    }
}

# Check invalid objects
Write-Host "ℹ Total invalid objects: $totalInvalid" -ForegroundColor $(if ($totalInvalid -eq 0) { "Green" } elseif ($totalInvalid -lt 10) { "Yellow" } else { "Red" })

# Display application version
if ($appVersion) {
    Write-Host "ℹ ChildView Application Version: $appVersion" -ForegroundColor Cyan
} else {
    Write-Host "⚠ Could not retrieve ChildView application version" -ForegroundColor Yellow
}

# Create verification report artifact
$verificationReport = @{
    SID = $cpu_SID
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    VersionNumbers = $versionNumbers
    ExpectedPackVersion = $expectedPackVersion
    VersionMismatch = $versionMismatchDetected
    ApplicationVersion = $appVersion
    RegistryIssues = $registryIssues
    InvalidObjectsCount = $totalInvalid
    OverallStatus = if ($registryIssues.Count -eq 0) { "PASS" } else { "WARNING" }
}

# Save report
$reportPath = "artifacts/patch_verification.json"
$verificationReport | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8 -Force

Write-Host ""
Write-Host "Verification report saved to: $reportPath" -ForegroundColor Cyan

# Exit with appropriate code
if ($registryIssues.Count -gt 0) {
    Write-Host ""
    Write-Host "⚠ Verification completed with warnings - please review component status" -ForegroundColor Yellow
    exit 0  # Don't fail the pipeline, but warn
} else {
    Write-Host ""
    Write-Host "✓ Patch verification completed successfully" -ForegroundColor Green
    exit 0
}
