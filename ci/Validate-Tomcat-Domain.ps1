<#
.SYNOPSIS
    Validate that the specified Tomcat domain exists on this server.

.DESCRIPTION
    This script checks if the Tomcat domain specified in the cpu_DOMAIN environment
    variable exists on the current server. If specified, validates against the detected
    Tomcat instances from the previous check job.

.PARAMETER cpu_DOMAIN
    The Tomcat domain name to validate (from environment variable)

.EXAMPLE
    .\Validate-Tomcat-Domain.ps1
    
.NOTES
    Author: Auto-generated for GitLab CI/CD
    Date: January 6, 2026
    Used by GitLab CI/CD pipeline
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Validating Tomcat Domain" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get environment variable
$cpuDomain = $env:cpu_DOMAIN

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  cpu_DOMAIN = $cpuDomain" -ForegroundColor White
Write-Host ""

# Check if tomcat_instances.json exists (from previous job)
$scriptDir = $PSScriptRoot
$baseDir = Split-Path $scriptDir -Parent
$tomcatJsonPath = Join-Path $baseDir "artifacts\tomcat_instances.json"

if (-not (Test-Path $tomcatJsonPath)) {
    Write-Host "⚠ No Tomcat instances detected - skipping validation" -ForegroundColor Yellow
    Write-Host "Expected to find: $tomcatJsonPath" -ForegroundColor Yellow
    exit 0
}

Write-Host "✓ Tomcat instances file found" -ForegroundColor Green

# Load Tomcat instances
try {
    $tomcatData = Get-Content $tomcatJsonPath | ConvertFrom-Json
    Write-Host ""
    Write-Host "Detected Tomcat Domains on $($tomcatData.Hostname):" -ForegroundColor Cyan
    foreach ($domain in $tomcatData.TomcatDomains) {
        Write-Host "  - Name: $($domain.Name), Home: $($domain.Home), Version: $($domain.Version)" -ForegroundColor White
    }
    Write-Host ""
} catch {
    Write-Host "ERROR: Could not read tomcat_instances.json: $_" -ForegroundColor Red
    exit 1
}

# If no domain specified, skip validation but show available domains
if ([string]::IsNullOrWhiteSpace($cpuDomain)) {
    Write-Host "⚠ No Tomcat domain specified in cpu_DOMAIN variable" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Available domains on this server:" -ForegroundColor Cyan
    foreach ($domain in $tomcatData.TomcatDomains) {
        Write-Host "  - $($domain.Name)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "Note: If cpu_DOMAIN is empty, patch will apply to ALL domains" -ForegroundColor Yellow
    exit 0
}

# Validate the specified domain exists
Write-Host "Validating domain: $cpuDomain" -ForegroundColor Cyan

$matchedDomain = $tomcatData.TomcatDomains | Where-Object { $_.Name -eq $cpuDomain }

if ($null -eq $matchedDomain) {
    Write-Host ""
    Write-Host "ERROR: Specified domain '$cpuDomain' not found on this server" -ForegroundColor Red
    Write-Host ""
    Write-Host "Available domains:" -ForegroundColor Yellow
    foreach ($domain in $tomcatData.TomcatDomains) {
        Write-Host "  - $($domain.Name)" -ForegroundColor White
    }
    Write-Host ""
    
    # Create marker file to indicate domain not found
    $artifactsDir = Join-Path $baseDir "artifacts"
    if (-not (Test-Path $artifactsDir)) {
        New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
    }
    
    $markerFile = Join-Path $artifactsDir "domain_not_found.marker"
    Set-Content -Path $markerFile -Value "Domain '$cpuDomain' not found on $(hostname) at $(Get-Date)"
    
    Write-Host "This server will skip Tomcat patching" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "✓ Domain validation successful" -ForegroundColor Green
Write-Host ""
Write-Host "Domain Details:" -ForegroundColor Cyan
Write-Host "  Name: $($matchedDomain.Name)" -ForegroundColor White
Write-Host "  Home: $($matchedDomain.Home)" -ForegroundColor White
Write-Host "  Base: $($matchedDomain.Base)" -ForegroundColor White
Write-Host "  Version: $($matchedDomain.Version)" -ForegroundColor White
Write-Host ""
Write-Host "Domain is ready for patching" -ForegroundColor Green
