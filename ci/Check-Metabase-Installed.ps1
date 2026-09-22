<#
.SYNOPSIS
    Check for installed Metabase instance on the server.

.DESCRIPTION
    This script discovers Metabase installation on the server by checking for the
    Metabase service and validating the installation structure. It creates a JSON 
    artifact with details about the Metabase instance found.

.EXAMPLE
    .\Check-Metabase-Installed.ps1
    
.NOTES
    Author: Auto-generated for GitLab CI/CD
    Date: January 22, 2026
    Used by GitLab CI/CD pipeline
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Checking for Metabase Installation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Determine base directory
$scriptDir = $PSScriptRoot
$baseDir = Split-Path $scriptDir -Parent

# Set up paths
$modulePath = Join-Path $baseDir "lib"
$resourcePath = Join-Path $baseDir "resource"
$packagePath = Join-Path $baseDir "package"
$logPath = Join-Path $baseDir "logs"

Write-Host "Base Directory: $baseDir" -ForegroundColor Gray
Write-Host ""

# Check for Metabase service
Write-Host "Searching for Metabase services..." -ForegroundColor Cyan

$metabaseServices = @(Get-Service -Name "*metabase*" -ErrorAction SilentlyContinue)

if ($metabaseServices.Count -eq 0) {
    Write-Host ""
    Write-Host "⚠ No Metabase services found on this server" -ForegroundColor Yellow
    Write-Host ""
    
    # Create artifacts directory
    $artifactsDir = Join-Path $baseDir "artifacts"
    if (-not (Test-Path $artifactsDir)) {
        New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
    }
    
    # Create marker file for no Metabase found
    $markerFile = Join-Path $artifactsDir "no_metabase_found.marker"
    Set-Content -Path $markerFile -Value "No Metabase service found on $(hostname) at $(Get-Date)"
    Write-Host "Created marker file: $markerFile" -ForegroundColor Gray
    
    # Create JSON artifact for reporting
    $output = @{
        Hostname = $env:COMPUTERNAME
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        MetabaseFound = $false
        Message = "No Metabase services found on this server"
        InstanceCount = 0
        Instances = @()
    }
    
    $jsonPath = Join-Path $artifactsDir "metabase_instance.json"
    $output | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath
    Write-Host "Created report artifact: $jsonPath" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "✓ Check completed - No Metabase instances to patch" -ForegroundColor Green
    exit 0
}

Write-Host "✓ Found $($metabaseServices.Count) Metabase service(s):" -ForegroundColor Green
foreach ($svc in $metabaseServices) {
    Write-Host "  - $($svc.Name) ($($svc.Status))" -ForegroundColor White
}
Write-Host ""

# Build list of all Metabase instances
$metabaseInstances = @()

foreach ($metabaseService in $metabaseServices) {
    Write-Host "Processing service: $($metabaseService.Name)" -ForegroundColor Cyan
    
    # Get service details
    $serviceInfo = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($metabaseService.Name)'"
    
    if (-not $serviceInfo) {
        Write-Host "  ⚠ Could not retrieve service information" -ForegroundColor Yellow
        continue
    }
    
    # Extract installation path from service PathName
    $servicePath = $serviceInfo.PathName
    Write-Host "  Service Path: $servicePath" -ForegroundColor Gray
    
    # Parse the path to find Metabase installation directory
    # Typical paths: 
    #   "D:\CACI\WebTier\portals\prod\metabase\winsw\winsw.exe"
    #   "C:\CACI\WebTier\Java\metabase\winsw.exe"
    $metabaseRoot = $null
    
    # Clean the service path - remove quotes and trim whitespace
    $cleanPath = $servicePath.Trim().Trim('"')
    
    if ($cleanPath -match '(.+)\\winsw\\winsw\.exe') {
        # Path includes \winsw\ subdirectory - go up one level
        $metabaseRoot = $matches[1].Trim()
    } elseif ($cleanPath -match '(.+)\\winsw\.exe') {
        # Path has winsw.exe directly in root
        $metabaseRoot = $matches[1].Trim()
    } else {
        Write-Host "  ⚠ Could not parse Metabase root from service path" -ForegroundColor Yellow
        $metabaseRoot = "Unknown"
    }
    
    # Check for metabase.jar
    $jarPath = $null
    $jarVersion = "Unknown"
    if ($metabaseRoot -and $metabaseRoot -ne "Unknown" -and (Test-Path $metabaseRoot)) {
        $jarPath = Join-Path $metabaseRoot "metabase.jar"
        if (Test-Path $jarPath) {
            Write-Host "  ✓ Found metabase.jar: $jarPath" -ForegroundColor Green
            
            # Try to read version from versions.xml first
            $versionsXmlPath = Join-Path $metabaseRoot "versions.xml"
            if (Test-Path $versionsXmlPath) {
                try {
                    [xml]$versionsXml = Get-Content $versionsXmlPath
                    $jarVersion = $versionsXml.versions.metabase
                    Write-Host "    Version: $jarVersion (from versions.xml)" -ForegroundColor White
                } catch {
                    Write-Host "    Version: Could not parse versions.xml" -ForegroundColor Yellow
                    $jarVersion = "Unknown"
                }
            } else {
                Write-Host "    Version: versions.xml not found" -ForegroundColor Yellow
                $jarVersion = "Unknown"
            }
        } else {
            Write-Host "  ⚠ metabase.jar not found at expected location" -ForegroundColor Yellow
        }
    }
    
    # Check for winsw.xml configuration (always in winsw subdirectory)
    $winswXml = $null
    $javaVersion = "Unknown"
    if ($metabaseRoot -and $metabaseRoot -ne "Unknown" -and (Test-Path $metabaseRoot)) {
        $winswXml = Join-Path $metabaseRoot "winsw\winsw.xml"
        
        if (Test-Path $winswXml) {
            Write-Host "  ✓ Found winsw.xml: $winswXml" -ForegroundColor Green
            
            # Parse XML to check Java version
            try {
                [xml]$config = Get-Content $winswXml
                $javaExecutable = $config.service.executable
                if ($javaExecutable -match 'jdk-?(\d+)') {
                    $javaVersion = $matches[1]
                    Write-Host "    Java Version: $javaVersion" -ForegroundColor White
                } elseif ($javaExecutable -match 'java') {
                    $javaVersion = "Found (version unclear)"
                    Write-Host "    Java executable found in config" -ForegroundColor White
                }
            } catch {
                Write-Host "    ⚠ Could not parse winsw.xml: $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  ⚠ winsw.xml not found at expected location" -ForegroundColor Yellow
        }
    }
    
    # Build Metabase instance info
    $instance = @{
        ServiceName = $metabaseService.Name
        ServiceStatus = $metabaseService.Status.ToString()
        ServiceDisplayName = $metabaseService.DisplayName
        InstallationRoot = $metabaseRoot
        JarPath = $jarPath
        JarVersion = $jarVersion
        WinswXmlPath = $winswXml
        JavaVersion = $javaVersion
    }
    
    $metabaseInstances += $instance
    Write-Host ""
}

# Create artifact with all instances
$metabaseData = @{
    Hostname = $env:COMPUTERNAME
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    MetabaseFound = $true
    InstanceCount = $metabaseInstances.Count
    Instances = $metabaseInstances
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary: Found $($metabaseInstances.Count) Metabase Instance(s)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
foreach ($inst in $metabaseInstances) {
    Write-Host "  Service: $($inst.ServiceName)" -ForegroundColor White
    Write-Host "    Status: $($inst.ServiceStatus)" -ForegroundColor White
    Write-Host "    Root: $($inst.InstallationRoot)" -ForegroundColor White
    Write-Host "    Java: $($inst.JavaVersion)" -ForegroundColor White
}
Write-Host ""

# Save to JSON artifact
$artifactsDir = Join-Path $baseDir "artifacts"
if (-not (Test-Path $artifactsDir)) {
    New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
}

$jsonPath = Join-Path $artifactsDir "metabase_instance.json"
$metabaseData | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath

Write-Host "✓ Metabase instance information saved to: $jsonPath" -ForegroundColor Green
Write-Host "  File size: $((Get-Item $jsonPath).Length) bytes" -ForegroundColor Gray
Write-Host ""
