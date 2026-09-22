<#
.SYNOPSIS
    Check for installed Tomcat instances on the server.

.DESCRIPTION
    This script discovers all Tomcat web tiers on the server by running the audit
    and parsing the Platform_config.xml file. It creates a JSON artifact with details
    about each Tomcat domain found.

.EXAMPLE
    .\Check-Tomcat-Installed.ps1
    
.NOTES
    Author: Auto-generated for GitLab CI/CD
    Date: January 6, 2026
    Used by GitLab CI/CD pipeline
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Checking for Tomcat Installations" -ForegroundColor Cyan
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
Write-Host "Module Path: $modulePath" -ForegroundColor Gray
Write-Host ""

# Import required modules
try {
    Import-Module (Join-Path $modulePath "Logging.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulePath "Folder-Ident.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulePath "tomcat_tools.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulePath "caci_utils.psm1") -Force -ErrorAction Stop
    Write-Host "✓ Successfully imported required modules" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to import required modules: $_" -ForegroundColor Red
    exit 1
}

# Set global variables for modules
$global:basedir = $baseDir
$global:module_path = $modulePath
$global:resource = $resourcePath
$global:package = $packagePath
$global:log_path = $logPath

Write-Host ""
Write-Host "Running audit to discover Tomcat instances..." -ForegroundColor Cyan

# Run audit to generate Platform_config.xml
try {
    $auditScript = Join-Path $modulePath "audit_get.ps1"
    if (Test-Path $auditScript) {
        & $auditScript
        Write-Host "✓ Audit completed successfully" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Audit script not found at: $auditScript" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "ERROR: Failed to run audit: $_" -ForegroundColor Red
    exit 1
}

# Check for Platform_config.xml
$configXml = Join-Path $baseDir "Platform_config.xml"
if (-not (Test-Path $configXml)) {
    Write-Host "ERROR: Platform_config.xml not found after audit" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Parsing Tomcat configuration..." -ForegroundColor Cyan

# Parse the XML to find Tomcat instances
try {
    [xml]$platform = Get-Content $configXml
    $webtiers = (Select-Xml -Xml $platform -XPath "//components/component[@type='web service']").Node
    
    if (-not $webtiers -or -not $webtiers.HasChildNodes) {
        Write-Host ""
        Write-Host "⚠ No Tomcat webtier instances found on this server" -ForegroundColor Yellow
        Write-Host ""
        
        # Create artifacts directory
        $artifactsDir = Join-Path $baseDir "artifacts"
        if (-not (Test-Path $artifactsDir)) {
            New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
        }
        
        # Create marker file for no Tomcat found
        $markerFile = Join-Path $artifactsDir "no_tomcat_found.marker"
        Set-Content -Path $markerFile -Value "No Tomcat instances found on $(hostname) at $(Get-Date)"
        Write-Host "Created marker file: $markerFile" -ForegroundColor Gray
        
        # Create JSON artifact for reporting
        $output = @{
            Hostname = $env:COMPUTERNAME
            DiscoveryDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            TomcatFound = $false
            Message = "No Tomcat webtier instances found on this server"
            TomcatDomains = @()
        }
        
        $jsonPath = Join-Path $artifactsDir "tomcat_instances.json"
        $output | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath
        Write-Host "Created report artifact: $jsonPath" -ForegroundColor Gray
        
        Write-Host ""
        Write-Host "✓ Check completed - No Tomcat instances to patch" -ForegroundColor Green
        exit 0
    }
    
    Write-Host "✓ Found Tomcat webtier instances" -ForegroundColor Green
    Write-Host ""
    
} catch {
    Write-Host "ERROR: Failed to parse Platform_config.xml: $_" -ForegroundColor Red
    exit 1
}

# Build list of Tomcat domains
$tomcatDomains = @()

foreach ($domain in $webtiers) {
    Write-Host "Processing domain: $($domain.name)" -ForegroundColor Cyan
    
    $domHome = $null
    $domBase = $null
    $catalinaHome = $null
    $serviceHome = $null
    
    foreach ($webFolder in $domain.folders.folder) {
        if ($webFolder.type -eq "service home") {
            $serviceHome = $webFolder.'#text'
            $domHome = ($serviceHome -split "\\bin\\tomcat")[0]
            $domHome = "$domHome\$($domain.name)"
        }
        if ($webFolder.type -eq "CATALINA_HOME") {
            $catalinaHome = $webFolder.'#text'
            $domHome = $catalinaHome
        }
    }
    
    if ($domHome) {
        $domBase = ($domHome -split "\\$($domain.name)")[0]
        
        # Get Tomcat version if possible
        $tomcatVersion = "Unknown"
        $versionFile = Join-Path $domHome "RELEASE-NOTES"
        if (Test-Path $versionFile) {
            $versionContent = Get-Content $versionFile -First 10
            $versionLine = $versionContent | Where-Object { $_ -match "Apache Tomcat Version" } | Select-Object -First 1
            if ($versionLine -match "Version\s+([\d\.]+)") {
                $tomcatVersion = $matches[1]
            }
        }
        
        $domainInfo = @{
            Name = $domain.name
            Home = $domHome
            Base = $domBase
            Version = $tomcatVersion
            ServiceHome = $serviceHome
            CatalinaHome = $catalinaHome
        }
        
        $tomcatDomains += $domainInfo
        
        Write-Host "  Name: $($domain.name)" -ForegroundColor White
        Write-Host "  Home: $domHome" -ForegroundColor White
        Write-Host "  Base: $domBase" -ForegroundColor White
        Write-Host "  Version: $tomcatVersion" -ForegroundColor White
        Write-Host ""
    } else {
        Write-Host "  ⚠ Could not determine home directory for domain: $($domain.name)" -ForegroundColor Yellow
        Write-Host ""
    }
}

if ($tomcatDomains.Count -eq 0) {
    Write-Host "⚠ No valid Tomcat domains found" -ForegroundColor Yellow
    
    # Create artifacts directory
    $artifactsDir = Join-Path $baseDir "artifacts"
    if (-not (Test-Path $artifactsDir)) {
        New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
    }
    
    # Create marker file
    $markerFile = Join-Path $artifactsDir "no_tomcat_found.marker"
    Set-Content -Path $markerFile -Value "No valid Tomcat domains found on $(hostname) at $(Get-Date)"
    Write-Host "Created marker file: $markerFile" -ForegroundColor Gray
    
    # Create JSON artifact for reporting
    $output = @{
        Hostname = $env:COMPUTERNAME
        DiscoveryDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        TomcatFound = $false
        Message = "No valid Tomcat domains found on this server"
        TomcatDomains = @()
    }
    
    $jsonPath = Join-Path $artifactsDir "tomcat_instances.json"
    $output | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath
    Write-Host "Created report artifact: $jsonPath" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "✓ Check completed - No Tomcat instances to patch" -ForegroundColor Green
    exit 0
}

# Create artifacts directory
$artifactsDir = Join-Path $baseDir "artifacts"
if (-not (Test-Path $artifactsDir)) {
    New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
}

# Create JSON output
$output = @{
    Hostname = $env:COMPUTERNAME
    DiscoveryDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    TomcatFound = $true
    TomcatDomains = $tomcatDomains
}

$jsonPath = Join-Path $artifactsDir "tomcat_instances.json"
$output | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Found $($tomcatDomains.Count) Tomcat domain(s)" -ForegroundColor Green
Write-Host "Artifact saved to: $jsonPath" -ForegroundColor Gray
Write-Host ""
Write-Host "✓ Check completed successfully" -ForegroundColor Green
