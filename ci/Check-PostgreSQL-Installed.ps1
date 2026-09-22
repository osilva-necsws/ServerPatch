<#
.SYNOPSIS
    Check for installed PostgreSQL instances on the server.

.DESCRIPTION
    This script discovers PostgreSQL installations on the server by checking for
    PostgreSQL services (pg_ctl). It creates a JSON artifact with details about
    each PostgreSQL instance found.

.EXAMPLE
    .\Check-PostgreSQL-Installed.ps1
    
.NOTES
    Author: Generated for GitLab CI/CD
    Date: January 28, 2026
    Used by GitLab CI/CD pipeline
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Checking for PostgreSQL Installations" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Determine base directory
$scriptDir = $PSScriptRoot
$baseDir = Split-Path $scriptDir -Parent

# Set up paths
$modulePath = Join-Path $baseDir "lib"
$artifactsDir = Join-Path $baseDir "artifacts"

Write-Host "Base Directory: $baseDir" -ForegroundColor Gray
Write-Host ""

# Check for PostgreSQL services
Write-Host "Searching for PostgreSQL services..." -ForegroundColor Cyan

$postgresServices = @(Get-CimInstance -ClassName Win32_Service | Where-Object { $_.PathName -like '*pg_ctl*' })

if ($postgresServices.Count -eq 0) {
    Write-Host ""
    Write-Host "⚠ No PostgreSQL services found on this server" -ForegroundColor Yellow
    Write-Host ""
    
    # Create artifacts directory
    if (-not (Test-Path $artifactsDir)) {
        New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
    }
    
    # Create marker file for no PostgreSQL found
    $markerFile = Join-Path $artifactsDir "no_postgresql_found.marker"
    Set-Content -Path $markerFile -Value "No PostgreSQL service found on $(hostname) at $(Get-Date)"
    Write-Host "Created marker file: $markerFile" -ForegroundColor Gray
    
    # Create JSON artifact for reporting
    $output = @{
        Hostname = $env:COMPUTERNAME
        DiscoveryDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        PostgreSQLFound = $false
        Message = "No PostgreSQL services found on this server"
        PostgreSQLInstances = @()
    }
    
    $jsonPath = Join-Path $artifactsDir "postgresql_instance.json"
    $output | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath
    Write-Host "Created report artifact: $jsonPath" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "✓ Check completed - No PostgreSQL instances to patch" -ForegroundColor Green
    exit 0
}

Write-Host "✓ Found $($postgresServices.Count) PostgreSQL service(s)" -ForegroundColor Green
Write-Host ""

# Build list of PostgreSQL instances
$postgresInstances = @()

foreach ($pgService in $postgresServices) {
    Write-Host "Processing service: $($pgService.Name)" -ForegroundColor Cyan
    
    # Extract pg_home from service PathName
    # Typical format: "C:\CACI\DBTier\PostgreSQL\pgsql-14.10\bin\pg_ctl.exe" runservice -N "ChildView_PostgreSQL" -D "C:\CACI\DBTier\PostgreSQL\pgsql-14.10\data"
    $servicePath = $pgService.PathName
    Write-Host "  Service Path: $servicePath" -ForegroundColor Gray
    
    $pgHome = $null
    $pgData = $null
    $pgVersion = "Unknown"
    
    # Parse pg_ctl path to get PGHOME
    if ($servicePath -match '"?([^"]+\\bin\\pg_ctl\.exe)"?') {
        $pgCtlPath = $matches[1]
        $pgHome = Split-Path (Split-Path $pgCtlPath -Parent) -Parent
        Write-Host "  PostgreSQL Home: $pgHome" -ForegroundColor White
    }
    
    # Parse data directory from -D parameter
    if ($servicePath -match '-D\s+"?([^"]+)"?') {
        $pgData = $matches[1]
        Write-Host "  Data Directory: $pgData" -ForegroundColor White
    }
    
    # Get PostgreSQL version
    if ($pgHome -and (Test-Path $pgHome)) {
        # Try to get version from PG_VERSION file
        $versionFile = Join-Path $pgData "PG_VERSION"
        if (Test-Path $versionFile) {
            $pgMajorVersion = Get-Content $versionFile -Raw
            $pgMajorVersion = $pgMajorVersion.Trim()
            Write-Host "  Major Version: $pgMajorVersion" -ForegroundColor White
        }
        
        # Get full version from pg_ctl
        $pgCtl = Join-Path $pgHome "bin\pg_ctl.exe"
        if (Test-Path $pgCtl) {
            try {
                $versionOutput = & $pgCtl --version 2>&1
                if ($versionOutput -match 'pg_ctl.*PostgreSQL.*?([\d\.]+)') {
                    $pgVersion = $matches[1]
                    Write-Host "  Full Version: $pgVersion" -ForegroundColor White
                }
            } catch {
                Write-Host "  ⚠ Could not determine full version" -ForegroundColor Yellow
            }
        }
        
        # Determine home directory name (e.g., pgsql-14.10)
        $pgHomeName = Split-Path $pgHome -Leaf
        Write-Host "  Home Name: $pgHomeName" -ForegroundColor White
    }
    
    $instance = @{
        ServiceName = $pgService.Name
        ServiceDisplayName = $pgService.DisplayName
        ServiceState = $pgService.State
        StartMode = $pgService.StartMode
        PostgreSQLHome = $pgHome
        DataDirectory = $pgData
        Version = $pgVersion
        HomeName = $pgHomeName
    }
    
    $postgresInstances += $instance
    Write-Host ""
}

# Create artifacts directory
if (-not (Test-Path $artifactsDir)) {
    New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
}

# Create JSON output
$output = @{
    Hostname = $env:COMPUTERNAME
    DiscoveryDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    PostgreSQLFound = $true
    PostgreSQLInstances = $postgresInstances
}

$jsonPath = Join-Path $artifactsDir "postgresql_instance.json"
$output | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Found $($postgresInstances.Count) PostgreSQL instance(s)" -ForegroundColor Green
foreach ($inst in $postgresInstances) {
    Write-Host "  Service: $($inst.ServiceName)" -ForegroundColor White
    Write-Host "    Status: $($inst.ServiceState)" -ForegroundColor White
    Write-Host "    Home: $($inst.PostgreSQLHome)" -ForegroundColor White
    Write-Host "    Version: $($inst.Version)" -ForegroundColor White
}
Write-Host ""
Write-Host "Artifact saved to: $jsonPath" -ForegroundColor Gray
Write-Host ""
Write-Host "✓ Check completed successfully" -ForegroundColor Green
