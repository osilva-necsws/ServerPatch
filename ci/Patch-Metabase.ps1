<#
.SYNOPSIS
    Execute Metabase patching process.

.DESCRIPTION
    This script validates environment variables and executes the Metabase patching.
    It stops the Metabase service, replaces the JAR file, checks winsw.xml for Java 21,
    and restarts the service.

.PARAMETER cpu_PatchMetabase
    The Artifactory URL for Metabase JAR file (from environment variable)

.EXAMPLE
    .\Patch-Metabase.ps1
    
.NOTES
    Author: Auto-generated for GitLab CI/CD
    Date: January 22, 2026
    Used by GitLab CI/CD pipeline
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Metabase Patching" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get environment variables
$cpuPatchMetabase = $env:cpu_PatchMetabase
$cpuPatchMetabaseOJDBC = $env:cpu_PatchMetabase_OJDBC

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Artifactory URL = $cpuPatchMetabase" -ForegroundColor White
Write-Host "  OJDBC URL = $cpuPatchMetabaseOJDBC" -ForegroundColor White
Write-Host ""

# Determine base directory
$scriptDir = $PSScriptRoot
$baseDir = Split-Path $scriptDir -Parent

# Check if metabase_instance.json exists (from previous job)
$metabaseJsonPath = Join-Path $baseDir "artifacts\metabase_instance.json"
if (-not (Test-Path $metabaseJsonPath)) {
    Write-Host "⚠ No Metabase instance detected - skipping patch" -ForegroundColor Yellow
    Write-Host "Expected to find: $metabaseJsonPath" -ForegroundColor Yellow
    exit 0
}

Write-Host "✓ Metabase instance detected at: $metabaseJsonPath" -ForegroundColor Green

# Load Metabase instance data
try {
    $metabaseData = Get-Content $metabaseJsonPath | ConvertFrom-Json
    Write-Host ""
    Write-Host "Metabase Instances Found: $($metabaseData.InstanceCount)" -ForegroundColor Cyan
    foreach ($inst in $metabaseData.Instances) {
        Write-Host "  - $($inst.ServiceName): $($inst.InstallationRoot)" -ForegroundColor White
    }
    Write-Host ""
} catch {
    Write-Host "⚠ Could not read metabase_instance.json: $_" -ForegroundColor Yellow
    exit 1
}

# Validate required environment variables
if ([string]::IsNullOrWhiteSpace($cpuPatchMetabase)) {
    Write-Host "ERROR: cpu_PatchMetabase environment variable is required for Patch Metabase action" -ForegroundColor Red
    exit 1
}

Write-Host "✓ All required environment variables are set" -ForegroundColor Green
Write-Host ""

# Set up paths
$packagePath = Join-Path $baseDir "package"
$logPath = Join-Path $baseDir "logs"

if (-not (Test-Path $packagePath)) {
    New-Item -Path $packagePath -ItemType Directory -Force | Out-Null
}

# Extract filename from URL
$metabaseFileName = Split-Path $cpuPatchMetabase -Leaf
$metabasePackagePath = Join-Path $packagePath $metabaseFileName

# Extract OJDBC filename if URL provided
$ojdbcFileName = $null
$ojdbcPackagePath = $null
if (-not [string]::IsNullOrWhiteSpace($cpuPatchMetabaseOJDBC)) {
    $ojdbcFileName = Split-Path $cpuPatchMetabaseOJDBC -Leaf
    $ojdbcPackagePath = Join-Path $packagePath $ojdbcFileName
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Downloading Metabase Package from Artifactory" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Package Information:" -ForegroundColor Cyan
Write-Host "  URL: $cpuPatchMetabase" -ForegroundColor White
Write-Host "  File: $metabaseFileName" -ForegroundColor White
Write-Host ""

# Download Metabase JAR
try {
    Write-Host "Downloading Metabase package from: $cpuPatchMetabase" -ForegroundColor Cyan
    Write-Host "Downloading to: $metabasePackagePath" -ForegroundColor Gray
    
    Invoke-WebRequest -Uri $cpuPatchMetabase -OutFile $metabasePackagePath -UseBasicParsing
    
    if (Test-Path $metabasePackagePath) {
        $fileSize = (Get-Item $metabasePackagePath).Length
        Write-Host "✓ Downloaded Metabase package ($([math]::Round($fileSize / 1MB, 2)) MB)" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Download appeared to succeed but file not found" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "ERROR: Failed to download Metabase package: $_" -ForegroundColor Red
    exit 1
}

# Download OJDBC JAR if URL provided
if (-not [string]::IsNullOrWhiteSpace($cpuPatchMetabaseOJDBC)) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Downloading OJDBC from Artifactory" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Package Information:" -ForegroundColor Cyan
    Write-Host "  URL: $cpuPatchMetabaseOJDBC" -ForegroundColor White
    Write-Host "  File: $ojdbcFileName" -ForegroundColor White
    Write-Host ""
    
    try {
        Write-Host "Downloading OJDBC from: $cpuPatchMetabaseOJDBC" -ForegroundColor Cyan
        Write-Host "Downloading to: $ojdbcPackagePath" -ForegroundColor Gray
        
        Invoke-WebRequest -Uri $cpuPatchMetabaseOJDBC -OutFile $ojdbcPackagePath -UseBasicParsing
        
        if (Test-Path $ojdbcPackagePath) {
            $fileSize = (Get-Item $ojdbcPackagePath).Length
            Write-Host "✓ Downloaded OJDBC ($([math]::Round($fileSize / 1KB, 2)) KB)" -ForegroundColor Green
        } else {
            Write-Host "ERROR: Download appeared to succeed but file not found" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "ERROR: Failed to download OJDBC: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host ""
    Write-Host "ℹ No OJDBC URL provided - skipping OJDBC download" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Patching Metabase Instances" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$patchedInstances = @()
$failedInstances = @()

foreach ($instance in $metabaseData.Instances) {
    Write-Host "-------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Processing: $($instance.ServiceName)" -ForegroundColor Cyan
    Write-Host "-------------------------------------------------------" -ForegroundColor Cyan
    Write-Host ""
    
    # Validate installation root exists
    if ($instance.InstallationRoot -eq "Unknown" -or -not (Test-Path $instance.InstallationRoot)) {
        Write-Host "ERROR: Installation root not found: $($instance.InstallationRoot)" -ForegroundColor Red
        $failedInstances += $instance.ServiceName
        continue
    }
    
    Write-Host "Installation root: $($instance.InstallationRoot)" -ForegroundColor White
    
    # Check winsw.xml for Java 21 (always in winsw subdirectory)
    $winswXmlPath = Join-Path $instance.InstallationRoot "winsw\winsw.xml"
    
    if (Test-Path $winswXmlPath) {
        try {
            [xml]$winswConfig = Get-Content $winswXmlPath
            $javaExecutable = $winswConfig.service.executable
            Write-Host "Java executable: $javaExecutable" -ForegroundColor White
            
            if ($javaExecutable -notmatch 'jdk-?21' -and $javaExecutable -notmatch 'java.*21') {
                Write-Host "⚠ WARNING: Java 21 not detected in winsw.xml" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "⚠ Could not parse winsw.xml" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    
    # Stop service
    Write-Host "Stopping service..." -ForegroundColor Cyan
    $service = Get-Service -Name $instance.ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "ERROR: Service not found: $($instance.ServiceName)" -ForegroundColor Red
        $failedInstances += $instance.ServiceName
        continue
    }
    
    if ($service.Status -eq 'Running') {
        try {
            Stop-Service -Name $instance.ServiceName -Force -ErrorAction Stop
            
            $timeout = 60
            $elapsed = 0
            while ((Get-Service -Name $instance.ServiceName).Status -ne 'Stopped' -and $elapsed -lt $timeout) {
                Start-Sleep -Seconds 2
                $elapsed += 2
            }
            
            $service = Get-Service -Name $instance.ServiceName
            if ($service.Status -eq 'Stopped') {
                Write-Host "✓ Service stopped" -ForegroundColor Green
            } else {
                Write-Host "ERROR: Service did not stop within $timeout seconds" -ForegroundColor Red
                $failedInstances += $instance.ServiceName
                continue
            }
        } catch {
            Write-Host "ERROR: Failed to stop service: $_" -ForegroundColor Red
            $failedInstances += $instance.ServiceName
            continue
        }
    } else {
        Write-Host "✓ Service already stopped" -ForegroundColor Green
    }
    
    # Backup current JAR
    $currentJarPath = Join-Path $instance.InstallationRoot "metabase.jar"
    if (Test-Path $currentJarPath) {
        $backupJarPath = Join-Path $instance.InstallationRoot "metabase.jar.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        try {
            Copy-Item -Path $currentJarPath -Destination $backupJarPath -Force
            Write-Host "✓ Backed up JAR" -ForegroundColor Green
        } catch {
            Write-Host "⚠ Could not backup JAR" -ForegroundColor Yellow
        }
    }
    
    # Deploy new JAR
    Write-Host "Deploying new JAR..." -ForegroundColor Cyan
    
    $isZip = $metabaseFileName -match '\.zip$'
    
    try {
        if ($isZip) {
            $extractPath = Join-Path $packagePath "metabase_extracted_$($instance.ServiceName)"
            if (Test-Path $extractPath) {
                Remove-Item -Path $extractPath -Recurse -Force
            }
            
            Expand-Archive -Path $metabasePackagePath -DestinationPath $extractPath -Force
            $extractedJar = Get-ChildItem -Path $extractPath -Filter "metabase.jar" -Recurse | Select-Object -First 1
            $extractedVersionXml = Get-ChildItem -Path $extractPath -Filter "versions.xml" -Recurse | Select-Object -First 1
            
            if ($extractedJar) {
                Copy-Item -Path $extractedJar.FullName -Destination $currentJarPath -Force
                Write-Host "✓ Deployed new JAR" -ForegroundColor Green
            } else {
                Write-Host "ERROR: No metabase.jar found in ZIP" -ForegroundColor Red
                $failedInstances += $instance.ServiceName
                Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
                continue
            }
            
            # Deploy versions.xml if found
            if ($extractedVersionXml) {
                $versionXmlPath = Join-Path $instance.InstallationRoot "versions.xml"
                Copy-Item -Path $extractedVersionXml.FullName -Destination $versionXmlPath -Force
                Write-Host "✓ Deployed versions.xml" -ForegroundColor Green
            } else {
                Write-Host "⚠ versions.xml not found in ZIP" -ForegroundColor Yellow
            }
            
            Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Copy-Item -Path $metabasePackagePath -Destination $currentJarPath -Force
            Write-Host "✓ Deployed new JAR" -ForegroundColor Green
        }
        
        $newJarSize = (Get-Item $currentJarPath).Length
        Write-Host "  JAR size: $([math]::Round($newJarSize / 1MB, 2)) MB" -ForegroundColor White
    } catch {
        Write-Host "ERROR: Failed to deploy JAR: $_" -ForegroundColor Red
        $failedInstances += $instance.ServiceName
        continue
    }
    
    # Delete plugins folder while service is stopped (best effort)
    $pluginsPath = Join-Path $instance.InstallationRoot "plugins"
    if (Test-Path $pluginsPath) {
        Write-Host "Deleting plugins folder..." -ForegroundColor Cyan
        try {
            Remove-Item -Path $pluginsPath -Recurse -Force -ErrorAction Stop
            Write-Host "✓ Deleted plugins folder" -ForegroundColor Green
        } catch {
            Write-Host "⚠ Could not delete plugins folder (may be locked by another process): $_" -ForegroundColor Yellow
            Write-Host "  Continuing with existing plugins - service will use current plugin versions" -ForegroundColor Yellow
        }
    } else {
        Write-Host "✓ No plugins folder to delete" -ForegroundColor Gray
    }
    
    # Deploy OJDBC to plugins folder before starting service (if available)
    if (-not [string]::IsNullOrWhiteSpace($ojdbcPackagePath) -and (Test-Path $ojdbcPackagePath)) {
        Write-Host "Pre-deploying OJDBC to plugins folder..." -ForegroundColor Cyan
        
        # Ensure plugins folder exists
        $pluginsPath = Join-Path $instance.InstallationRoot "plugins"
        if (-not (Test-Path $pluginsPath)) {
            New-Item -Path $pluginsPath -ItemType Directory -Force | Out-Null
            Write-Host "✓ Created plugins folder" -ForegroundColor Green
        }
        
        try {
            $ojdbcDestPath = Join-Path $pluginsPath $ojdbcFileName
            Copy-Item -Path $ojdbcPackagePath -Destination $ojdbcDestPath -Force -ErrorAction Stop
            Write-Host "✓ Pre-deployed OJDBC (will be loaded on service start)" -ForegroundColor Green
        } catch {
            Write-Host "⚠ Could not pre-deploy OJDBC: $_" -ForegroundColor Yellow
        }
    }
    
    # Start service to let Metabase create plugins folder and extract built-in plugins
    Write-Host "Starting service..." -ForegroundColor Cyan
    try {
        Start-Service -Name $instance.ServiceName -ErrorAction Stop
        
        $timeout = 120
        $elapsed = 0
        while ((Get-Service -Name $instance.ServiceName).Status -ne 'Running' -and $elapsed -lt $timeout) {
            Start-Sleep -Seconds 5
            $elapsed += 5
        }
        
        $service = Get-Service -Name $instance.ServiceName
        if ($service.Status -eq 'Running') {
            Write-Host "✓ Service started successfully" -ForegroundColor Green
            
            # Deploy OJDBC to plugins folder if available and plugins were deleted
            $ojdbcDeployed = $false
            if (-not [string]::IsNullOrWhiteSpace($ojdbcPackagePath) -and (Test-Path $ojdbcPackagePath)) {
                
                if (-not $pluginsDeleted) {
                    Write-Host "⚠ Skipping OJDBC deployment - plugins folder was not deleted (may contain existing OJDBC)" -ForegroundColor Yellow
                } else {
                    Write-Host "Deploying OJDBC to plugins folder..." -ForegroundColor Cyan
                
                # Wait for Metabase to create plugins folder
                $pluginsPath = Join-Path $instance.InstallationRoot "plugins"
                $waitCount = 0
                $maxWait = 30
                
                Write-Host "Waiting for Metabase to create plugins folder..." -ForegroundColor Gray
                while (-not (Test-Path $pluginsPath) -and $waitCount -lt $maxWait) {
                    Start-Sleep -Seconds 2
                    $waitCount += 2
                }
                
                if (Test-Path $pluginsPath) {
                    Write-Host "✓ Plugins folder created by Metabase" -ForegroundColor Green
                    
                    # Stop service to avoid file locks during OJDBC copy
                    Write-Host "Stopping service to deploy OJDBC..." -ForegroundColor Cyan
                    try {
                        Stop-Service -Name $instance.ServiceName -Force -ErrorAction Stop
                        
                        $timeout = 60
                        $elapsed = 0
                        while ((Get-Service -Name $instance.ServiceName).Status -ne 'Stopped' -and $elapsed -lt $timeout) {
                            Start-Sleep -Seconds 2
                            $elapsed += 2
                        }
                        
                        if ((Get-Service -Name $instance.ServiceName).Status -eq 'Stopped') {
                            Write-Host "✓ Service stopped" -ForegroundColor Green
                            
                            # Copy OJDBC to plugins folder
                            $ojdbcDestPath = Join-Path $pluginsPath $ojdbcFileName
                            Copy-Item -Path $ojdbcPackagePath -Destination $ojdbcDestPath -Force -ErrorAction Stop
                            Write-Host "✓ Deployed OJDBC to plugins folder" -ForegroundColor Green
                            
                            # Start service to load all plugins including OJDBC
                            Write-Host "Starting service to load all plugins..." -ForegroundColor Cyan
                            Start-Service -Name $instance.ServiceName -ErrorAction Stop
                            
                            $timeout = 120
                            $elapsed = 0
                            while ((Get-Service -Name $instance.ServiceName).Status -ne 'Running' -and $elapsed -lt $timeout) {
                                Start-Sleep -Seconds 5
                                $elapsed += 5
                            }
                            
                            $service = Get-Service -Name $instance.ServiceName
                            if ($service.Status -eq 'Running') {
                                Write-Host "✓ Service started successfully with OJDBC plugin" -ForegroundColor Green
                                $ojdbcDeployed = $true
                            } else {
                                Write-Host "ERROR: Service did not start within $timeout seconds" -ForegroundColor Red
                                $failedInstances += $instance.ServiceName
                                continue
                            }
                        } else {
                            Write-Host "ERROR: Service did not stop within $timeout seconds" -ForegroundColor Red
                            $failedInstances += $instance.ServiceName
                            continue
                        }
                    } catch {
                        Write-Host "ERROR: Failed during OJDBC deployment: $_" -ForegroundColor Red
                        $failedInstances += $instance.ServiceName
                        # Try to restart service
                        try {
                            Start-Service -Name $instance.ServiceName -ErrorAction SilentlyContinue
                        } catch {}
                        continue
                    }
                } else {
                    Write-Host "ERROR: Plugins folder not created within $maxWait seconds" -ForegroundColor Red
                    $failedInstances += $instance.ServiceName
                    continue
                }
                }
            }
            
            # Delete backup file after successful start
            if ($backupJarPath -and (Test-Path $backupJarPath)) {
                try {
                    Remove-Item -Path $backupJarPath -Force
                    Write-Host "✓ Deleted backup file: $backupJarPath" -ForegroundColor Green
                } catch {
                    Write-Host "⚠ Could not delete backup file: $_" -ForegroundColor Yellow
                }
            }
            
            $patchedInstances += @{
                ServiceName = $instance.ServiceName
                InstallationRoot = $instance.InstallationRoot
                NewJarSize = $newJarSize
                PluginsDeleted = $pluginsDeleted
                OJDBCDeployed = $ojdbcDeployed
            }
        } else {
            Write-Host "ERROR: Service did not start within $timeout seconds" -ForegroundColor Red
            $failedInstances += $instance.ServiceName
        }
    } catch {
        Write-Host "ERROR: Failed to start service: $_" -ForegroundColor Red
        $failedInstances += $instance.ServiceName
    }
    
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Metabase Patching Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  ✓ Successfully patched: $($patchedInstances.Count)" -ForegroundColor Green
Write-Host "  ✗ Failed: $($failedInstances.Count)" -ForegroundColor $(if ($failedInstances.Count -gt 0) { "Red" } else { "Green" })

if ($failedInstances.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed instances:" -ForegroundColor Red
    foreach ($failed in $failedInstances) {
        Write-Host "  - $failed" -ForegroundColor Red
    }
}

Write-Host ""

# Create completion artifact
$artifactsDir = Join-Path $baseDir "artifacts"
if (-not (Test-Path $artifactsDir)) {
    New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
}

$completionInfo = @{
    Hostname = $env:COMPUTERNAME
    PatchDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    MetabasePackage = $metabaseFileName
    ArtifactoryURL = $cpuPatchMetabase
    PatchedInstances = $patchedInstances
    FailedInstances = $failedInstances
    SuccessCount = $patchedInstances.Count
    FailedCount = $failedInstances.Count
}

$completionPath = Join-Path $artifactsDir "metabase_patch_complete.json"
$completionInfo | ConvertTo-Json -Depth 10 | Set-Content -Path $completionPath

Write-Host "Patch completion artifact saved to: $completionPath" -ForegroundColor Gray
Write-Host ""

# Exit with error if any instance failed
if ($failedInstances.Count -gt 0) {
    exit 1
}
