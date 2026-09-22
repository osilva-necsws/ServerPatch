<#
.SYNOPSIS
    Check for installed Apache instances.
#>

[CmdletBinding()]
param()

$baseDir = Split-Path $PSScriptRoot -Parent
$artifactsDir = Join-Path $baseDir "artifacts"

if (-not (Test-Path $artifactsDir)) {
    New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
}

Write-Host "Searching for Apache services..." -ForegroundColor Cyan
$apacheServices = Get-CimInstance -ClassName Win32_Service -Filter "PathName LIKE '%httpd.exe%'"

$instances = @()

if (-not $apacheServices -or $apacheServices.Count -eq 0) {
    Write-Host "⚠ No Apache services found on this server." -ForegroundColor Yellow
    $output = @{
        Hostname = $env:COMPUTERNAME
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        ApacheFound = $false
        Message = "No Apache services found"
    }
} else {
    foreach ($service in $apacheServices) {
        $installDir = $null
        if ($service.PathName -match '"?(.+)\\bin\\httpd\.exe"?') {
            $installDir = $matches[1].Trim()
            $versionOutput = & "$installDir\bin\httpd.exe" -v 2>&1
            $versionMatches = $versionOutput | Select-String -Pattern "Server version: Apache/([\d\.]+)"
            $version = if ($versionMatches) { $versionMatches.Matches.Groups[1].Value } else { "Unknown" }
            
            $instances += @{
                ServiceName = $service.Name
                InstallDir = $installDir
                Version = $version
            }
        }
    }
    
    $output = @{
        Hostname = $env:COMPUTERNAME
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        ApacheFound = $true
        Instances = $instances
    }
}

$jsonPath = Join-Path $artifactsDir "apache_instance.json"
$output | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath
Write-Host "Created report artifact: $jsonPath" -ForegroundColor Gray
exit 0
