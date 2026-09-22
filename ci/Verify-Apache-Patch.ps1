<#
.SYNOPSIS
    Verify successful Apache patch installation.
#>

[CmdletBinding()]
param()

$baseDir = Split-Path $PSScriptRoot -Parent
$artifactsDir = Join-Path $baseDir "artifacts"
$patchCompletePath = Join-Path $artifactsDir "apache_patch_complete.json"

if (-not (Test-Path $patchCompletePath)) {
    Write-Host "No patch completion artifact found - skipping verification" -ForegroundColor Yellow
    exit 0
}

Write-Host "Verifying Apache services..." -ForegroundColor Cyan
$apacheServices = Get-CimInstance -ClassName Win32_Service -Filter "PathName LIKE '%httpd.exe%'"

$allGood = $true
$results = @()

foreach ($service in $apacheServices) {
    $installDir = $null
    if ($service.PathName -match '"?(.+)\\bin\\httpd\.exe"?') {
        $installDir = $matches[1].Trim()
        $versionOutput = & "$installDir\bin\httpd.exe" -v 2>&1
        $versionMatches = $versionOutput | Select-String -Pattern "Server version: Apache/([\d\.]+)"
        $version = if ($versionMatches) { $versionMatches.Matches.Groups[1].Value } else { "Unknown" }
        
        $state = $service.State
        Write-Host "Service: $($service.Name) - State: $state - Version: $version" -ForegroundColor White
        
        $isRunning = ($state -eq "Running")
        if (-not $isRunning) {
            Write-Host "⚠ Service is not running!" -ForegroundColor Red
            $allGood = $false
        }
        
        $results += @{
            ServiceName = $service.Name
            Version = $version
            IsRunning = $isRunning
        }
    }
}

$output = @{
    Hostname = $env:COMPUTERNAME
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    VerificationPassed = $allGood
    Results = $results
}

$jsonPath = Join-Path $artifactsDir "apache_verification.json"
$output | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath

if (-not $allGood) {
    Write-Host "Apache verification failed!" -ForegroundColor Red
    exit 1
}

Write-Host "Apache verification completed successfully!" -ForegroundColor Green
exit 0
