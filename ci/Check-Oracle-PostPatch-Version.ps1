[CmdletBinding()]
param(
    [switch]$FailOnMismatch
)

Write-Host "================================" -ForegroundColor Cyan
Write-Host "Oracle Post-Patch Version Check" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

function Get-OracleHomeFromService {
    param(
        [Parameter(Mandatory)]
        [string]$Sid
    )

    $serviceName = "OracleService$Sid"
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
    if (-not $svc) {
        throw "Windows service '$serviceName' not found"
    }

    $pathName = [string]$svc.PathName
    if ([string]::IsNullOrWhiteSpace($pathName)) {
        throw "Service '$serviceName' has empty PathName"
    }

    $m = [regex]::Match($pathName, '"?([A-Za-z]:\\[^"\s]+\\bin\\ORACLE\.EXE)"?', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $m.Success) {
        throw "Could not parse ORACLE.EXE path from PathName: $pathName"
    }

    $exePath = $m.Groups[1].Value
    $binDir = Split-Path -Parent $exePath
    $oracleHomeResolved = Split-Path -Parent $binDir
    if (-not (Test-Path $oracleHomeResolved)) {
        throw "Resolved ORACLE_HOME does not exist: $oracleHomeResolved"
    }

    return $oracleHomeResolved
}

$workspaceArtifacts = Join-Path $PSScriptRoot "..\artifacts"
$noDbMarker = Join-Path $workspaceArtifacts "no_databases_found.marker"
$sidNotFoundMarker = Join-Path $workspaceArtifacts "sid_not_found.marker"
$rerunMarker = Join-Path $workspaceArtifacts "datapatch_rerun_needed.marker"
$reportPath = Join-Path $workspaceArtifacts "oracle_version_check.json"

if (Test-Path $noDbMarker) {
    Write-Host "⚠ No Oracle databases found on server - skipping version check" -ForegroundColor Yellow
    if (Test-Path $rerunMarker) { Remove-Item $rerunMarker -Force -ErrorAction SilentlyContinue }
    exit 0
}

if (Test-Path $sidNotFoundMarker) {
    Write-Host "⚠ SID validation did not find a match - skipping version check" -ForegroundColor Yellow
    if (Test-Path $rerunMarker) { Remove-Item $rerunMarker -Force -ErrorAction SilentlyContinue }
    exit 0
}

$cpu_SID = $env:cpu_SID

if ([string]::IsNullOrWhiteSpace($cpu_SID)) {
    Write-Host "❌ ERROR: cpu_SID environment variable is not set" -ForegroundColor Red
    exit 1
}

$oracleHome = $null
try {
    $oracleHome = Get-OracleHomeFromService -Sid $cpu_SID
    Write-Host "Resolved ORACLE_HOME from service: $oracleHome" -ForegroundColor Cyan
} catch {
    Write-Host "❌ ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$env:ORACLE_HOME = $oracleHome
$env:ORACLE_SID = $cpu_SID

$sqlplusPath = Join-Path $oracleHome "bin\sqlplus.exe"
if (-not (Test-Path $sqlplusPath)) {
    Write-Host "❌ ERROR: sqlplus.exe not found at $sqlplusPath" -ForegroundColor Red
    exit 1
}

# Retrieve expected version from the local pack_oracle_dbhome.xml (Artifactory no longer used)
$expectedPackVersion = $null
try {
    $packageFolder = Join-Path $PSScriptRoot "..\package"
    $tempPackXml = Join-Path $packageFolder "pack_oracle_dbhome.xml"

    Write-Host "Reading pack metadata: $tempPackXml" -ForegroundColor Cyan

    if (Test-Path $tempPackXml) {
        [xml]$packXml = Get-Content $tempPackXml
        $expectedPackVersion = $packXml.Objs.Obj.MS.S | Where-Object { $_.N -eq 'version' } | Select-Object -ExpandProperty '#text'
    } else {
        Write-Host "⚠ WARNING: pack_oracle_dbhome.xml not found in package folder" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠ WARNING: Could not retrieve pack version: $($_.Exception.Message)" -ForegroundColor Yellow
}

if ($expectedPackVersion) {
    $expectedPackVersion = $expectedPackVersion.Trim()
}

if ([string]::IsNullOrWhiteSpace($expectedPackVersion)) {
    Write-Host "⚠ WARNING: Expected pack version unavailable; cannot compare versions" -ForegroundColor Yellow
}

# Fallback check: dba_registry version_full + status
$sqlScript = @"
SET PAGESIZE 0
SET LINESIZE 300
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT EXPECTED_PACK|$expectedPackVersion

SELECT 'INVALID_COUNT|' || COUNT(*)
FROM dba_registry
WHERE status = 'INVALID';

SELECT 'VERSIONS|' || LISTAGG(v, ',') WITHIN GROUP (ORDER BY v)
FROM (
  SELECT DISTINCT REGEXP_SUBSTR(version_full, '^[0-9]+\.[0-9]+\.[0-9]+') AS v
  FROM dba_registry
  WHERE comp_name NOT LIKE '%Application Express%'
);

SELECT 'MISMATCH_COUNT|' || COUNT(*)
FROM (
  SELECT DISTINCT REGEXP_SUBSTR(version_full, '^[0-9]+\.[0-9]+\.[0-9]+') AS v
  FROM dba_registry
  WHERE comp_name NOT LIKE '%Application Express%'
)
WHERE TRIM('$expectedPackVersion') <> ''
    AND v <> TRIM('$expectedPackVersion');

EXIT;
"@

$tempSqlFile = Join-Path $env:TEMP "postpatch_registry_check_$($cpu_SID).sql"
$sqlScript | Out-File -FilePath $tempSqlFile -Encoding ASCII -Force

$sqlOutput = & $sqlplusPath -S "/ as sysdba" "@$tempSqlFile" 2>&1
Remove-Item $tempSqlFile -Force -ErrorAction SilentlyContinue

$invalidCount = $null
$versionsCsv = $null
$mismatchCount = $null

foreach ($line in ($sqlOutput -split "`n")) {
    $t = $line.Trim()
    if ($t -like 'INVALID_COUNT|*') { $invalidCount = [int]($t.Split('|')[1]) }
    if ($t -like 'VERSIONS|*') { $versionsCsv = $t.Substring('VERSIONS|'.Length) }
    if ($t -like 'MISMATCH_COUNT|*') { $mismatchCount = [int]($t.Split('|')[1]) }
}

if ($null -eq $invalidCount -or $null -eq $versionsCsv -or $null -eq $mismatchCount) {
    Write-Host "❌ ERROR: Could not parse dba_registry check output" -ForegroundColor Red
    Write-Host ($sqlOutput | Out-String)
    exit 1
}

$needsRerun = $false
if ($invalidCount -gt 0) {
    $needsRerun = $true
}
if (-not [string]::IsNullOrWhiteSpace($expectedPackVersion) -and $mismatchCount -gt 0) {
    $needsRerun = $true
}

Write-Host "" 
Write-Host "Pack expected version:  $expectedPackVersion" -ForegroundColor Cyan
Write-Host "DBA_REGISTRY versions:  $versionsCsv" -ForegroundColor Cyan
Write-Host "INVALID components:     $invalidCount" -ForegroundColor Cyan
Write-Host "Version mismatch count: $mismatchCount" -ForegroundColor Cyan

if ($needsRerun) {
    Write-Host "⚠ Registry check indicates mismatch/invalid components; datapatch rerun required" -ForegroundColor Yellow
    if (-not (Test-Path $workspaceArtifacts)) {
        New-Item -Path $workspaceArtifacts -ItemType Directory -Force | Out-Null
    }
    "DATAPATCH_RERUN_NEEDED" | Out-File -FilePath $rerunMarker -Force
} else {
    Write-Host "✓ Registry check OK; datapatch rerun not required" -ForegroundColor Green
    if (Test-Path $rerunMarker) { Remove-Item $rerunMarker -Force -ErrorAction SilentlyContinue }
}

$report = [ordered]@{
    SID = $cpu_SID
    Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    OracleHome = $oracleHome
    ExpectedPackVersion = $expectedPackVersion
    RegistryVersions = $versionsCsv
    InvalidRegistryCount = $invalidCount
    VersionMismatchCount = $mismatchCount
    NeedsDatapatchRerun = $needsRerun
}

if (-not (Test-Path $workspaceArtifacts)) {
    New-Item -Path $workspaceArtifacts -ItemType Directory -Force | Out-Null
}
$report | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8 -Force
Write-Host "Report saved to: $reportPath" -ForegroundColor Cyan

if ($needsRerun -and $FailOnMismatch) { exit 1 }

exit 0
