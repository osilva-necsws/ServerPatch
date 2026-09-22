[CmdletBinding()]
param(
    [int]$DelaySeconds = 30,
    [int]$MaxAttempts = 3,
    [int]$RetryDelaySeconds = 180
)

Write-Host "================================" -ForegroundColor Cyan
Write-Host "Datapatch Rerun (If Needed)" -ForegroundColor Cyan
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
$rerunMarker = Join-Path $workspaceArtifacts "datapatch_rerun_needed.marker"
$dbuaStatusPath = Join-Path $workspaceArtifacts "dbua_datapatch_status.json"
$noDbMarker = Join-Path $workspaceArtifacts "no_databases_found.marker"
$sidNotFoundMarker = Join-Path $workspaceArtifacts "sid_not_found.marker"
$logPath = Join-Path $workspaceArtifacts "datapatch_rerun.log"

if (Test-Path $noDbMarker) {
    Write-Host "⚠ No Oracle databases found on server - skipping datapatch rerun" -ForegroundColor Yellow
    exit 0
}

if (Test-Path $sidNotFoundMarker) {
    Write-Host "⚠ SID validation did not find a match - skipping datapatch rerun" -ForegroundColor Yellow
    exit 0
}

# If DBUA already ran datapatch successfully (exit status 0), do NOT rerun datapatch.
# If DBUA reported non-zero (e.g. 1), rerun datapatch regardless of marker.
$dbuaDatapatchExit = $null
if (Test-Path $dbuaStatusPath) {
    try {
        $dbuaStatus = Get-Content $dbuaStatusPath -Raw | ConvertFrom-Json
        if ($null -ne $dbuaStatus.DatapatchExitStatus) {
            $dbuaDatapatchExit = [int]$dbuaStatus.DatapatchExitStatus
            Write-Host "DBUA datapatch exit status: $dbuaDatapatchExit" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "⚠ WARNING: Could not parse ${dbuaStatusPath}: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if ($dbuaDatapatchExit -eq 0) {
    Write-Host "✓ DBUA reported datapatch succeeded; skipping datapatch rerun" -ForegroundColor Green
    exit 0
}

if ($null -ne $dbuaDatapatchExit -and $dbuaDatapatchExit -ne 0) {
    Write-Host "⚠ DBUA reported datapatch failed (exit $dbuaDatapatchExit); will rerun datapatch" -ForegroundColor Yellow
} else {
    # No DBUA datapatch status; fall back to marker-based decision.
    if (-not (Test-Path $rerunMarker)) {
        Write-Host "✓ No version mismatch marker found; skipping datapatch" -ForegroundColor Green
        exit 0
    }
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

# Ensure ORACLE_HOME bin and OPatch are on PATH
$env:PATH = "$oracleHome\bin;$oracleHome\OPatch;$($env:PATH)"

$datapatchBat = Join-Path $oracleHome "OPatch\datapatch.bat"
$datapatchExe = Join-Path $oracleHome "OPatch\datapatch"

$datapatch = $null
if (Test-Path $datapatchBat) {
    $datapatch = $datapatchBat
} elseif (Test-Path $datapatchExe) {
    $datapatch = $datapatchExe
}

if (-not $datapatch) {
    Write-Host "❌ ERROR: datapatch not found under $oracleHome\OPatch" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $workspaceArtifacts)) {
    New-Item -Path $workspaceArtifacts -ItemType Directory -Force | Out-Null
}

"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Running datapatch -verbose (SID=$cpu_SID, ORACLE_HOME=$oracleHome)" | Out-File -FilePath $logPath -Encoding UTF8 -Force

if ($MaxAttempts -lt 1) { $MaxAttempts = 1 }
if ($RetryDelaySeconds -lt 0) { $RetryDelaySeconds = 0 }

$exitCode = 1
for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    $attemptHeader = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Attempt $attempt/${MaxAttempts}: datapatch -verbose"
    $attemptHeader | Out-File -FilePath $logPath -Append -Encoding UTF8

    Write-Host "Running (attempt $attempt/$MaxAttempts): $datapatch -verbose" -ForegroundColor Cyan
    & $datapatch -verbose 2>&1 | Tee-Object -FilePath $logPath -Append
    $exitCode = $LASTEXITCODE

    Write-Host "datapatch exit code: $exitCode" -ForegroundColor Cyan
    if ($exitCode -eq 0) {
        break
    }

    $lockLikeFailure = Select-String -Path $logPath -Pattern 'ORA-20016|Unable to get the lock|get_pending_activity|verify_queryable_inventory' -Quiet
    if ($lockLikeFailure -and $attempt -lt $MaxAttempts) {
        Write-Host "⚠ datapatch failed due to an inventory/lock prereq (ORA-20016). Retrying in $RetryDelaySeconds seconds..." -ForegroundColor Yellow
        if ($RetryDelaySeconds -gt 0) {
            Start-Sleep -Seconds $RetryDelaySeconds
        }
        continue
    }

    Write-Host "❌ ERROR: datapatch failed" -ForegroundColor Red
    exit $exitCode
}

if ($exitCode -ne 0) {
    Write-Host "❌ ERROR: datapatch failed after $MaxAttempts attempt(s)" -ForegroundColor Red
    exit $exitCode
}

Write-Host "Sleeping $DelaySeconds seconds to allow registry to settle..." -ForegroundColor Yellow
Start-Sleep -Seconds $DelaySeconds

# Re-check version and fail if still mismatched
& (Join-Path $PSScriptRoot "Check-Oracle-PostPatch-Version.ps1") -FailOnMismatch
exit $LASTEXITCODE
