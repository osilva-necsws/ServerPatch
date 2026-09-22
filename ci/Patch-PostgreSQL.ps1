<#
.SYNOPSIS
    Execute PostgreSQL minor version patching process.

.DESCRIPTION
    This script patches PostgreSQL by stopping the service, replacing binaries,
    and starting the service. Supports minor version upgrades (e.g., 14.10 -> 14.11).

.PARAMETER cpu_PatchPostgreSQL
    The Artifactory URL for PostgreSQL patch files (from environment variable)

.EXAMPLE
    .\Patch-PostgreSQL.ps1
    
.NOTES
    Author: Generated for GitLab CI/CD
    Date: January 28, 2026
    Used by GitLab CI/CD pipeline
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PostgreSQL Minor Version Patching" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get environment variables
$cpuPatchPostgreSQL = $env:cpu_PatchPostgreSQL
$cpuPatchPostgreSQL_v15 = $env:cpu_PatchPostgreSQL_v15
$cpuPatchPostgreSQL_Orafce = $env:cpu_PatchPostgreSQL_Orafce

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  PostgreSQL v14 URL = $cpuPatchPostgreSQL" -ForegroundColor White
Write-Host "  PostgreSQL v15 URL = $cpuPatchPostgreSQL_v15" -ForegroundColor White
Write-Host "  Orafce Extension URL = $cpuPatchPostgreSQL_Orafce" -ForegroundColor White
Write-Host ""

# Determine base directory
$scriptDir = $PSScriptRoot
$baseDir = Split-Path $scriptDir -Parent

# Check if postgresql_instance.json exists (from previous job)
$postgresJsonPath = Join-Path $baseDir "artifacts\postgresql_instance.json"
if (-not (Test-Path $postgresJsonPath)) {
    Write-Host "⚠ No PostgreSQL instances detected - skipping patch" -ForegroundColor Yellow
    Write-Host "Expected to find: $postgresJsonPath" -ForegroundColor Yellow
    
    # Create empty artifact to avoid upload warning
    $artifactsDir = Join-Path $baseDir "artifacts"
    if (-not (Test-Path $artifactsDir)) {
        New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
    }
    
    $skipInfo = @{
        Hostname = $env:COMPUTERNAME
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        PatchSkipped = $true
        Reason = "No PostgreSQL instances found"
    }
    
    $skipJsonPath = Join-Path $artifactsDir "postgresql_patch_complete.json"
    $skipInfo | ConvertTo-Json | Set-Content -Path $skipJsonPath
    
    exit 0
}

Write-Host "✓ PostgreSQL instances detected at: $postgresJsonPath" -ForegroundColor Green

# Display detected PostgreSQL instances and check if any were found
try {
    $postgresData = Get-Content $postgresJsonPath | ConvertFrom-Json
    
    # Check if PostgreSQL was actually found
    if ($postgresData.PostgreSQLFound -eq $false) {
        Write-Host ""
        Write-Host "⏭️ No PostgreSQL instances found on this server - skipping patch" -ForegroundColor Cyan
        
        # Create artifact indicating skip
        $artifactsDir = Join-Path $baseDir "artifacts"
        if (-not (Test-Path $artifactsDir)) {
            New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
        }
        
        $skipInfo = @{
            Hostname = $env:COMPUTERNAME
            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            PatchSkipped = $true
            Reason = "No PostgreSQL instances found on this server"
            PostgreSQLFound = $false
        }
        
        $skipJsonPath = Join-Path $artifactsDir "postgresql_patch_complete.json"
        $skipInfo | ConvertTo-Json | Set-Content -Path $skipJsonPath
        
        Write-Host "✓ Skip status recorded in artifact" -ForegroundColor Green
        exit 0
    }
    
    Write-Host ""
    Write-Host "Detected PostgreSQL Instances:" -ForegroundColor Cyan
    foreach ($instance in $postgresData.PostgreSQLInstances) {
        Write-Host "  - Service: $($instance.ServiceName), Home: $($instance.PostgreSQLHome), Version: $($instance.Version)" -ForegroundColor White
    }
    Write-Host ""
} catch {
    Write-Host "ERROR: Could not read postgresql_instance.json: $_" -ForegroundColor Red
    exit 1
}

# Validate required environment variables
$validationFailed = $false

if ([string]::IsNullOrWhiteSpace($cpuPatchPostgreSQL) -and [string]::IsNullOrWhiteSpace($cpuPatchPostgreSQL_v15)) {
    Write-Host "ERROR: At least one PostgreSQL package URL is required (cpu_PatchPostgreSQL or cpu_PatchPostgreSQL_v15)" -ForegroundColor Red
    $validationFailed = $true
}

if ($validationFailed) {
    Write-Host ""
    Write-Host "Please set the required environment variables and try again." -ForegroundColor Red
    exit 1
}

Write-Host "✓ Required environment variables are set" -ForegroundColor Green
Write-Host ""

# Set up paths
$modulePath = Join-Path $baseDir "lib"
$resourcePath = Join-Path $baseDir "resource"
$packagePath = Join-Path $baseDir "package"
$logPath = Join-Path $baseDir "logs"

# Set global variables for modules
$global:basedir = $baseDir
$global:module_path = $modulePath
$global:resource = $resourcePath
$global:package_path = $packagePath
$global:log_path = $logPath

# Import required modules
Write-Host "Importing required modules..." -ForegroundColor Cyan
try {
    Import-Module (Join-Path $modulePath "Logging.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulePath "caci_utils.psm1") -Force -ErrorAction Stop
    Write-Host "✓ Successfully imported required modules" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to import required modules: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Downloading PostgreSQL Packages from Artifactory" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Prepare list of packages to download
$packagesToDownload = @()

if (-not [string]::IsNullOrWhiteSpace($cpuPatchPostgreSQL)) {
    $packagesToDownload += @{
        URL = $cpuPatchPostgreSQL
        Version = "v14"
    }
}

if (-not [string]::IsNullOrWhiteSpace($cpuPatchPostgreSQL_v15)) {
    $packagesToDownload += @{
        URL = $cpuPatchPostgreSQL_v15
        Version = "v15"
    }
}

Write-Host "Packages to download: $($packagesToDownload.Count)" -ForegroundColor Cyan
Write-Host ""

# Download and extract all packages
$extractedPackages = @()

foreach ($pkg in $packagesToDownload) {
    $packageUrl = $pkg.URL
    $packageVersion = $pkg.Version
    $packageFileName = Split-Path $packageUrl -Leaf
    
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host "Downloading $packageVersion package" -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host "Package Information:" -ForegroundColor Cyan
    Write-Host "  URL: $packageUrl" -ForegroundColor White
    Write-Host "  File: $packageFileName" -ForegroundColor White
    Write-Host ""
    
    # Download package
    $packageLocalPath = Join-Path $packagePath $packageFileName
    
    Write-Host "Downloading to: $packageLocalPath" -ForegroundColor Gray
    
    try {
        # Create package directory if it doesn't exist
        if (-not (Test-Path $packagePath)) {
            New-Item -Path $packagePath -ItemType Directory -Force | Out-Null
        }
        
        # Download the file
        Invoke-WebRequest -Uri $packageUrl -OutFile $packageLocalPath -ErrorAction Stop
        
        if (Test-Path $packageLocalPath) {
            $fileSize = (Get-Item $packageLocalPath).Length
            Write-Host "✓ Downloaded package ($([math]::Round($fileSize / 1MB, 2)) MB)" -ForegroundColor Green
        } else {
            throw "Package file not found after download"
        }
    } catch {
        Write-Host "ERROR: Failed to download package: $_" -ForegroundColor Red
        continue
    }
    
    # Calculate MD5 checksum
    Write-Host "Calculating checksum..." -ForegroundColor Gray
    try {
        $md5 = Get-FileHash -Path $packageLocalPath -Algorithm MD5
        Write-Host "  MD5: $($md5.Hash)" -ForegroundColor White
    } catch {
        Write-Host "⚠ Could not calculate MD5: $_" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "Extracting package..." -ForegroundColor Cyan
    
    # Extract to temporary location
    $extractPath = Join-Path $packagePath "postgres_temp_extract_$packageVersion"
    if (Test-Path $extractPath) {
        Remove-Item -Path $extractPath -Recurse -Force
    }
    
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($packageLocalPath, $extractPath)
        Write-Host "✓ Package extracted successfully" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to extract package: $_" -ForegroundColor Red
        continue
    }
    
    # Find the pgsql directory in the extracted content
    $pgsqlPath = Get-ChildItem -Path $extractPath -Directory | Where-Object { $_.Name -eq "pgsql" } | Select-Object -First 1
    if (-not $pgsqlPath) {
        Write-Host "ERROR: Could not find 'pgsql' directory in extracted package" -ForegroundColor Red
        continue
    }
    
    # Detect actual version from extracted pg_ctl binary
    $detectedVersion = "Unknown"
    $extractedPgCtl = Join-Path $pgsqlPath.FullName "bin\pg_ctl.exe"
    if (Test-Path $extractedPgCtl) {
        try {
            $versionOutput = & $extractedPgCtl --version 2>&1
            if ($versionOutput -match 'pg_ctl.*PostgreSQL.*?([\d\.]+)') {
                $detectedVersion = $matches[1]
                Write-Host "Detected version from binaries: $detectedVersion" -ForegroundColor Cyan
            }
        } catch {
            Write-Host "⚠ Could not determine version from binaries" -ForegroundColor Yellow
        }
    }
    
    # Extract major version
    $majorVersion = "Unknown"
    if ($detectedVersion -match '^(\d+)\.') {
        $majorVersion = $matches[1]
    }
    
    $extractedPackages += @{
        Version = $detectedVersion
        MajorVersion = $majorVersion
        PgsqlPath = $pgsqlPath.FullName
        ExtractPath = $extractPath
        PackageFileName = $packageFileName
        PackageURL = $packageUrl
    }
    
    Write-Host "✓ Package ready - PostgreSQL $detectedVersion (Major: $majorVersion)" -ForegroundColor Green
    Write-Host ""
}

if ($extractedPackages.Count -eq 0) {
    Write-Host "ERROR: No packages were successfully downloaded and extracted" -ForegroundColor Red
    exit 1
}

# Download and extract orafce extension if URL provided
$orafceExtracted = $null
if (-not [string]::IsNullOrWhiteSpace($cpuPatchPostgreSQL_Orafce)) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Downloading Orafce Extension" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $orafceFileName = Split-Path $cpuPatchPostgreSQL_Orafce -Leaf
    $orafceLocalPath = Join-Path $packagePath $orafceFileName
    
    Write-Host "Package Information:" -ForegroundColor Cyan
    Write-Host "  URL: $cpuPatchPostgreSQL_Orafce" -ForegroundColor White
    Write-Host "  File: $orafceFileName" -ForegroundColor White
    Write-Host ""
    
    try {
        Write-Host "Downloading to: $orafceLocalPath" -ForegroundColor Gray
        Invoke-WebRequest -Uri $cpuPatchPostgreSQL_Orafce -OutFile $orafceLocalPath -ErrorAction Stop
        
        if (Test-Path $orafceLocalPath) {
            $fileSize = (Get-Item $orafceLocalPath).Length
            Write-Host "✓ Downloaded orafce package ($([math]::Round($fileSize / 1KB, 2)) KB)" -ForegroundColor Green
        } else {
            throw "Package file not found after download"
        }
        
        Write-Host ""
        Write-Host "Extracting orafce package..." -ForegroundColor Cyan
        
        $orafceExtractPath = Join-Path $packagePath "orafce_extract"
        if (Test-Path $orafceExtractPath) {
            Remove-Item -Path $orafceExtractPath -Recurse -Force
        }
        
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($orafceLocalPath, $orafceExtractPath)
        
        # Verify structure: lib/14, lib/15, extension/
        $orafceLibPath = Join-Path $orafceExtractPath "lib"
        $orafceExtensionPath = Join-Path $orafceExtractPath "extension"
        
        if ((Test-Path $orafceLibPath) -and (Test-Path $orafceExtensionPath)) {
            Write-Host "✓ Orafce package extracted successfully" -ForegroundColor Green
            $orafceExtracted = @{
                LibPath = $orafceLibPath
                ExtensionPath = $orafceExtensionPath
                ExtractPath = $orafceExtractPath
            }
        } else {
            Write-Host "⚠ Orafce package structure incorrect - expected 'lib' and 'extension' folders" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "ERROR: Failed to download/extract orafce: $_" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Version Compatibility Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Group instances by major version and match with extracted packages
$patchPlans = @()
$skippedInstances = @()

foreach ($instance in $postgresData.PostgreSQLInstances) {
    $currentVersion = $instance.Version
    $currentMajorVersion = "Unknown"
    
    if ($currentVersion -match '^(\d+)\.') {
        $currentMajorVersion = $matches[1]
    }
    
    Write-Host "$($instance.ServiceName): Current=$currentVersion (Major: $currentMajorVersion)" -ForegroundColor White
    
    # Find matching package for this instance
    $matchingPackage = $extractedPackages | Where-Object { $_.MajorVersion -eq $currentMajorVersion } | Select-Object -First 1
    
    if ($matchingPackage) {
        Write-Host "  ✓ Will patch to $($matchingPackage.Version)" -ForegroundColor Green
        $patchPlans += @{
            Instance = $instance
            Package = $matchingPackage
        }
    } else {
        Write-Host "  ⚠ No matching package found for major version $currentMajorVersion" -ForegroundColor Yellow
        $skippedInstances += $instance
    }
}

Write-Host ""

if ($patchPlans.Count -eq 0) {
    Write-Host "⚠ No compatible PostgreSQL instances found to patch" -ForegroundColor Yellow
    Write-Host "No instances match the major versions of the provided packages." -ForegroundColor Yellow
    Write-Host ""
    
    # Create artifact indicating skip
    $artifactsDir = Join-Path $baseDir "artifacts"
    if (-not (Test-Path $artifactsDir)) {
        New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
    }
    
    $skipInfo = @{
        Hostname = $env:COMPUTERNAME
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        PatchSkipped = $true
        Reason = "No compatible instances found for provided packages"
        ProvidedPackages = @($extractedPackages | ForEach-Object {
            @{
                Version = $_.Version
                MajorVersion = $_.MajorVersion
            }
        })
        SkippedInstances = @($skippedInstances | ForEach-Object {
            @{
                ServiceName = $_.ServiceName
                CurrentVersion = $_.Version
                MajorVersion = if ($_.Version -match '^(\d+)\.') { $matches[1] } else { "Unknown" }
            }
        })
    }
    
    $skipJsonPath = Join-Path $artifactsDir "postgresql_patch_complete.json"
    $skipInfo | ConvertTo-Json -Depth 10 | Set-Content -Path $skipJsonPath
    
    # Cleanup extraction directories
    foreach ($pkg in $extractedPackages) {
        if (Test-Path $pkg.ExtractPath) {
            Remove-Item -Path $pkg.ExtractPath -Recurse -Force
        }
    }
    
    Write-Host "✓ Skip status recorded in artifact" -ForegroundColor Green
    exit 0
}

Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Instances to patch: $($patchPlans.Count)" -ForegroundColor Green
Write-Host "  Skipped instances: $($skippedInstances.Count)" -ForegroundColor Yellow
Write-Host ""

# Patch each instance according to plan
$patchedInstances = @()

foreach ($plan in $patchPlans) {
    $instance = $plan.Instance
    $package = $plan.Package
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Patching: $($instance.ServiceName)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    $pgHome = $instance.PostgreSQLHome
    $serviceName = $instance.ServiceName
    $currentVersion = $instance.Version
    $newVersion = $package.Version
    $pgsqlPath = $package.PgsqlPath
    
    Write-Host "Current Version: $currentVersion" -ForegroundColor White
    Write-Host "Target Version: $newVersion" -ForegroundColor White
    Write-Host "PostgreSQL Home: $pgHome" -ForegroundColor White
    Write-Host ""
    
    # Stop the PostgreSQL service
    Write-Host "Stopping PostgreSQL service..." -ForegroundColor Cyan
    try {
        Stop-Service -Name $serviceName -Force -ErrorAction Stop
        Write-Host "✓ Service stopped" -ForegroundColor Green
        
        # Wait for service to fully stop
        $timeout = 30
        $elapsed = 0
        while ((Get-Service -Name $serviceName).Status -ne 'Stopped' -and $elapsed -lt $timeout) {
            Start-Sleep -Seconds 1
            $elapsed++
        }
        
        if ((Get-Service -Name $serviceName).Status -ne 'Stopped') {
            throw "Service did not stop within $timeout seconds"
        }
    } catch {
        Write-Host "ERROR: Failed to stop service: $_" -ForegroundColor Red
        continue
    }
    
    Write-Host ""
    Write-Host "Backing up current binaries..." -ForegroundColor Cyan
    
    # Backup bin and lib directories
    $backupPath = Join-Path $pgHome "backup_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
    try {
        New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
        
        # Backup bin directory
        $binBackup = Join-Path $backupPath "bin"
        Copy-Item -Path (Join-Path $pgHome "bin") -Destination $binBackup -Recurse -Force
        
        # Backup lib directory
        $libBackup = Join-Path $backupPath "lib"
        Copy-Item -Path (Join-Path $pgHome "lib") -Destination $libBackup -Recurse -Force
        
        Write-Host "✓ Backup created at: $backupPath" -ForegroundColor Green
    } catch {
        Write-Host "⚠ Warning: Could not create backup: $_" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "Replacing PostgreSQL binaries..." -ForegroundColor Cyan
    
    # Replace bin and lib directories
    try {
        # Replace bin directory
        Write-Host "  Replacing bin directory..." -ForegroundColor Gray
        $sourceBin = Join-Path $pgsqlPath "bin"
        $targetBin = Join-Path $pgHome "bin"
        
        Remove-Item -Path $targetBin -Recurse -Force
        Copy-Item -Path $sourceBin -Destination $targetBin -Recurse -Force
        
        # Replace lib directory
        Write-Host "  Replacing lib directory..." -ForegroundColor Gray
        $sourceLib = Join-Path $pgsqlPath "lib"
        $targetLib = Join-Path $pgHome "lib"
        
        Remove-Item -Path $targetLib -Recurse -Force
        Copy-Item -Path $sourceLib -Destination $targetLib -Recurse -Force
        
        # Replace share directory
        Write-Host "  Replacing share directory..." -ForegroundColor Gray
        $sourceShare = Join-Path $pgsqlPath "share"
        $targetShare = Join-Path $pgHome "share"
        
        Remove-Item -Path $targetShare -Recurse -Force
        Copy-Item -Path $sourceShare -Destination $targetShare -Recurse -Force
        
        Write-Host "✓ Binaries replaced successfully" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to replace binaries: $_" -ForegroundColor Red
        
        # Attempt to restore from backup
        if (Test-Path $backupPath) {
            Write-Host "Attempting to restore from backup..." -ForegroundColor Yellow
            try {
                Copy-Item -Path (Join-Path $backupPath "bin") -Destination (Join-Path $pgHome "bin") -Recurse -Force
                Copy-Item -Path (Join-Path $backupPath "lib") -Destination (Join-Path $pgHome "lib") -Recurse -Force
                Write-Host "✓ Restored from backup" -ForegroundColor Green
            } catch {
                Write-Host "ERROR: Failed to restore from backup: $_" -ForegroundColor Red
            }
        }
        continue
    }
    
    # Deploy orafce extension if available
    if ($orafceExtracted) {
        Write-Host ""
        Write-Host "Deploying orafce extension..." -ForegroundColor Cyan
        
        # Determine major version for this instance
        $instanceMajorVersion = "Unknown"
        if ($currentVersion -match '^(\d+)\.') {
            $instanceMajorVersion = $matches[1]
        }
        
        # Deploy DLL from correct version folder
        $orafceDllSource = Join-Path $orafceExtracted.LibPath "$instanceMajorVersion\orafce.dll"
        if (Test-Path $orafceDllSource) {
            try {
                $orafceDllTarget = Join-Path $pgHome "lib\orafce.dll"
                Copy-Item -Path $orafceDllSource -Destination $orafceDllTarget -Force
                Write-Host "  ✓ Deployed orafce.dll for PostgreSQL $instanceMajorVersion" -ForegroundColor Green
            } catch {
                Write-Host "  ⚠ Could not deploy orafce.dll: $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  ⚠ orafce.dll not found for version $instanceMajorVersion" -ForegroundColor Yellow
        }
        
        # Deploy extension files (SQL and control)
        try {
            $targetExtensionPath = Join-Path $pgHome "share\extension"
            if (-not (Test-Path $targetExtensionPath)) {
                New-Item -Path $targetExtensionPath -ItemType Directory -Force | Out-Null
            }
            
            $extensionFiles = Get-ChildItem -Path $orafceExtracted.ExtensionPath -Filter "orafce*"
            foreach ($file in $extensionFiles) {
                Copy-Item -Path $file.FullName -Destination $targetExtensionPath -Force
            }
            Write-Host "  ✓ Deployed orafce extension files ($($extensionFiles.Count) files)" -ForegroundColor Green
        } catch {
            Write-Host "  ⚠ Could not deploy extension files: $_" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    Write-Host "Starting PostgreSQL service..." -ForegroundColor Cyan
    try {
        Start-Service -Name $serviceName -ErrorAction Stop
        Write-Host "✓ Service started" -ForegroundColor Green
        
        # Wait for service to start
        $timeout = 30
        $elapsed = 0
        while ((Get-Service -Name $serviceName).Status -ne 'Running' -and $elapsed -lt $timeout) {
            Start-Sleep -Seconds 1
            $elapsed++
        }
        
        if ((Get-Service -Name $serviceName).Status -eq 'Running') {
            Write-Host "✓ Service is running" -ForegroundColor Green
            
            # Delete backup since service started successfully
            if (Test-Path $backupPath) {
                Write-Host "Deleting backup directory..." -ForegroundColor Cyan
                try {
                    Remove-Item -Path $backupPath -Recurse -Force
                    Write-Host "✓ Backup deleted successfully" -ForegroundColor Green
                } catch {
                    Write-Host "⚠ Warning: Could not delete backup: $_" -ForegroundColor Yellow
                }
            }
        } else {
            throw "Service did not start within $timeout seconds"
        }
    } catch {
        Write-Host "ERROR: Failed to start service: $_" -ForegroundColor Red
        continue
    }
    
    Write-Host ""
    Write-Host "✓ Patch completed for $serviceName" -ForegroundColor Green
    Write-Host ""
    
    $patchedInstances += @{
        ServiceName = $serviceName
        OldVersion = $currentVersion
        NewVersion = $newVersion
        TargetVersion = $newVersion
        PatchTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        BackupPath = $backupPath
        PackageURL = $package.PackageURL
        Success = $true
    }
}

# Cleanup extraction directories
foreach ($pkg in $extractedPackages) {
    if (Test-Path $pkg.ExtractPath) {
        Remove-Item -Path $pkg.ExtractPath -Recurse -Force
    }
}

# Cleanup orafce extraction directory
if ($orafceExtracted -and (Test-Path $orafceExtracted.ExtractPath)) {
    Remove-Item -Path $orafceExtracted.ExtractPath -Recurse -Force
}

# Create completion artifact
$artifactsDir = Join-Path $baseDir "artifacts"
if (-not (Test-Path $artifactsDir)) {
    New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
}

$completionInfo = @{
    Hostname = $env:COMPUTERNAME
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Packages = @($extractedPackages | ForEach-Object {
        @{
            FileName = $_.PackageFileName
            URL = $_.PackageURL
            Version = $_.Version
            MajorVersion = $_.MajorVersion
        }
    })
    OrafceDeployed = ($null -ne $orafceExtracted)
    OrafceURL = if ($orafceExtracted) { $cpuPatchPostgreSQL_Orafce } else { $null }
    PatchedInstances = $patchedInstances
    TotalInstances = $patchedInstances.Count
    SkippedInstances = @($skippedInstances | ForEach-Object {
        @{
            ServiceName = $_.ServiceName
            CurrentVersion = $_.Version
            MajorVersion = if ($_.Version -match '^(\d+)\.') { $matches[1] } else { "Unknown" }
            Reason = "No matching package found"
        }
    })
    SkippedCount = $skippedInstances.Count
}

$completionJsonPath = Join-Path $artifactsDir "postgresql_patch_complete.json"
$completionInfo | ConvertTo-Json -Depth 10 | Set-Content -Path $completionJsonPath

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Patch Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Successfully patched: $($patchedInstances.Count) PostgreSQL instance(s)" -ForegroundColor Green
if ($skippedInstances.Count -gt 0) {
    Write-Host "Skipped (no matching package): $($skippedInstances.Count) instance(s)" -ForegroundColor Yellow
    foreach ($skipped in $skippedInstances) {
        Write-Host "  - $($skipped.ServiceName) (v$($skipped.Version))" -ForegroundColor Yellow
    }
}
Write-Host "Completion artifact saved to: $completionJsonPath" -ForegroundColor Gray
Write-Host ""
Write-Host "✓ PostgreSQL patching completed" -ForegroundColor Green
