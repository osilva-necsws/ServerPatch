<#
.SYNOPSIS
    Check for running Oracle databases on the server.

.DESCRIPTION
    This script checks for the existence of running Oracle databases by:
    - Checking for Oracle services that are running
    - Attempting to identify Oracle Database instances
    - Checking Oracle processes
    - Verifying listener status

.EXAMPLE
    .\Check-OracleDatabases.ps1
    
.NOTES
    Author: Auto-generated
    Date: November 12, 2025
#>

[CmdletBinding()]
param()

function Write-Status {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    switch ($Type) {
        "Success" { Write-Host "[$timestamp] [SUCCESS] $Message" -ForegroundColor Green }
        "Warning" { Write-Host "[$timestamp] [WARNING] $Message" -ForegroundColor Yellow }
        "Error"   { Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor Red }
        default   { Write-Host "[$timestamp] [INFO] $Message" -ForegroundColor Cyan }
    }
}

function Get-OracleServices {
    Write-Status "Checking for Oracle services..."
    
    $oracleServices = Get-Service -ErrorAction SilentlyContinue | Where-Object { 
        $_.Name -like "Oracle*" -or $_.DisplayName -like "*Oracle*"
    }
    
    if ($oracleServices) {
        Write-Status "Found $($oracleServices.Count) Oracle service(s)" "Success"
        $oracleServices | ForEach-Object {
            $status = if ($_.Status -eq 'Running') { "Success" } else { "Warning" }
            Write-Status "  - $($_.DisplayName): $($_.Status)" $status
        }
        return $oracleServices
    } else {
        Write-Status "No Oracle services found" "Warning"
        return $null
    }
}

function Get-OracleProcesses {
    Write-Status "Checking for Oracle processes..."
    
    $oracleProcesses = Get-Process | Where-Object { 
        $_.ProcessName -like "oracle*" -or 
        $_.ProcessName -eq "tnslsnr" -or
        $_.ProcessName -like "ORACLE*"
    }
    
    if ($oracleProcesses) {
        Write-Status "Found $($oracleProcesses.Count) Oracle process(es) running" "Success"
        $oracleProcesses | Group-Object ProcessName | ForEach-Object {
            Write-Status "  - $($_.Name): $($_.Count) instance(s)" "Success"
        }
        return $oracleProcesses
    } else {
        Write-Status "No Oracle processes found" "Warning"
        return $null
    }
}

function Get-OracleHomes {
    Write-Status "Searching for Oracle homes..."
    
    $oracleHomes = @()
    
    # Check registry for Oracle homes
    $registryPaths = @(
        "HKLM:\SOFTWARE\ORACLE",
        "HKLM:\SOFTWARE\WOW6432Node\ORACLE"
    )
    
    foreach ($regPath in $registryPaths) {
        if (Test-Path $regPath) {
            try {
                $keys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
                foreach ($key in $keys) {
                    $oracleHome = (Get-ItemProperty -Path $key.PSPath -Name "ORACLE_HOME" -ErrorAction SilentlyContinue).ORACLE_HOME
                    if ($oracleHome -and (Test-Path $oracleHome)) {
                        $oracleHomes += $oracleHome
                    }
                }
            } catch {
                # Silently continue if registry access fails
            }
        }
    }
    
    if ($oracleHomes) {
        $oracleHomes = $oracleHomes | Select-Object -Unique
        Write-Status "Found $($oracleHomes.Count) Oracle home(s)" "Success"
        $oracleHomes | ForEach-Object {
            Write-Status "  - $_" "Success"
        }
        return $oracleHomes
    } else {
        Write-Status "No Oracle homes found in registry" "Warning"
        return $null
    }
}

function Get-OracleDatabaseInstances {
    Write-Status "Identifying Oracle database instances..."
    
    $instances = @()
    
    # Check for database services (typically OracleService<SID>)
    $dbServices = Get-Service -ErrorAction SilentlyContinue | Where-Object { 
        $_.Name -like "OracleService*" 
    }
    
    if ($dbServices) {
        foreach ($service in $dbServices) {
            $sid = $service.Name -replace "OracleService", ""
            
            # Try to find Oracle Home for this instance
            $oracleHome = $null
            $registryPath = "HKLM:\SOFTWARE\ORACLE\KEY_$sid"
            
            if (Test-Path $registryPath) {
                try {
                    $oracleHome = (Get-ItemProperty -Path $registryPath -Name "ORACLE_HOME" -ErrorAction SilentlyContinue).ORACLE_HOME
                } catch {
                    # Silently continue
                }
            }
            
            # If not found in registry, try to get it from service ImagePath
            if (-not $oracleHome) {
                try {
                    $servicePath = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$($service.Name)'" -ErrorAction SilentlyContinue).PathName
                    if ($servicePath) {
                        # Extract path from service executable (typically ORACLE_HOME\bin\ORACLE.EXE)
                        if ($servicePath -match '(.+?)\\bin\\') {
                            $oracleHome = $matches[1].Trim('"')
                        }
                    }
                } catch {
                    # Silently continue
                }
            }
            
            $instances += [PSCustomObject]@{
                SID = $sid
                ServiceName = $service.Name
                Status = $service.Status
                StartType = $service.StartType
                OracleHome = $oracleHome
            }
        }
        
        Write-Status "Found $($instances.Count) Oracle database instance(s)" "Success"
        $instances | ForEach-Object {
            $status = if ($_.Status -eq 'Running') { "Success" } else { "Warning" }
            $homeInfo = if ($_.OracleHome) { ", Oracle Home: $($_.OracleHome)" } else { "" }
            Write-Status "  - SID: $($_.SID), Status: $($_.Status), StartType: $($_.StartType)$homeInfo" $status
        }
        return $instances
    } else {
        Write-Status "No Oracle database instances found" "Warning"
        return $null
    }
}

function Get-OracleListeners {
    Write-Status "Checking for Oracle listeners..."
    
    $listenerServices = Get-Service -ErrorAction SilentlyContinue | Where-Object { 
        $_.Name -like "OracleOraHome*TNSListener*" -or
        $_.Name -like "Oracle*Listener*" -or
        $_.DisplayName -like "*TNS Listener*"
    }
    
    if ($listenerServices) {
        Write-Status "Found $($listenerServices.Count) Oracle listener(s)" "Success"
        $listenerServices | ForEach-Object {
            $status = if ($_.Status -eq 'Running') { "Success" } else { "Warning" }
            Write-Status "  - $($_.DisplayName): $($_.Status)" $status
        }
        return $listenerServices
    } else {
        Write-Status "No Oracle listener services found" "Warning"
        return $null
    }
}

# Main execution
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Oracle Database Detection Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$results = @{
    Services = Get-OracleServices
    Processes = Get-OracleProcesses
    Homes = Get-OracleHomes
    Instances = Get-OracleDatabaseInstances
    Listeners = Get-OracleListeners
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$hasRunningDatabases = $false

if ($results.Instances) {
    $runningInstances = $results.Instances | Where-Object { $_.Status -eq 'Running' }
    if ($runningInstances) {
        $hasRunningDatabases = $true
        Write-Status "Running Oracle Databases: $($runningInstances.Count)" "Success"
        $runningInstances | ForEach-Object {
            Write-Host "    SID: $($_.SID)" -ForegroundColor Green
        }
    } else {
        Write-Status "No running Oracle databases found (services exist but are stopped)" "Warning"
    }
} else {
    Write-Status "No Oracle database instances detected on this server" "Warning"
}

if ($results.Listeners) {
    $runningListeners = $results.Listeners | Where-Object { $_.Status -eq 'Running' }
    if ($runningListeners) {
        Write-Status "Running Oracle Listeners: $($runningListeners.Count)" "Success"
    }
}

Write-Host ""

# Exit code: 0 if running databases found, 1 if not
if ($hasRunningDatabases) {
    Write-Status "Oracle databases are running on this server" "Success"
    
    # Create JSON output with Oracle database information
    # Primary location: workspace artifacts directory
    $workspaceArtifactsPath = Join-Path $PSScriptRoot "..\artifacts"
    $jsonFile = Join-Path $workspaceArtifactsPath "oracle_databases.json"
    
    # Secondary location: shared config directory
    $sharedConfigPath = "D:\CACI\Config\cpu_Oraclepath"
    $sharedJsonFile = Join-Path $sharedConfigPath "oracle_databases.json"
    
    try {
        # Create workspace artifacts directory if it doesn't exist
        if (-not (Test-Path $workspaceArtifactsPath)) {
            Write-Status "Creating artifacts directory: $workspaceArtifactsPath" "Info"
            New-Item -Path $workspaceArtifactsPath -ItemType Directory -Force | Out-Null
        }
        
        # Create shared config directory if it doesn't exist
        if (-not (Test-Path $sharedConfigPath)) {
            Write-Status "Creating shared config directory: $sharedConfigPath" "Info"
            New-Item -Path $sharedConfigPath -ItemType Directory -Force | Out-Null
        }
        
        # Prepare JSON data
        $jsonData = @{
            Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            ServerName = $env:COMPUTERNAME
            RunningDatabases = @()
            OracleHomes = @()
            Listeners = @()
        }
        
        # Add running database instances
        if ($results.Instances) {
            $runningInstances = $results.Instances | Where-Object { $_.Status -eq 'Running' }
            foreach ($instance in $runningInstances) {
                $jsonData.RunningDatabases += @{
                    SID = $instance.SID
                    ServiceName = $instance.ServiceName
                    Status = $instance.Status.ToString()
                    StartType = $instance.StartType.ToString()
                    OracleHome = $instance.OracleHome
                }
            }
        }
        
        # Add Oracle homes
        if ($results.Homes) {
            $jsonData.OracleHomes = @($results.Homes)
        }
        
        # Add running listeners
        if ($results.Listeners) {
            $runningListeners = $results.Listeners | Where-Object { $_.Status -eq 'Running' }
            foreach ($listener in $runningListeners) {
                $jsonData.Listeners += @{
                    Name = $listener.Name
                    DisplayName = $listener.DisplayName
                    Status = $listener.Status.ToString()
                }
            }
        }
        
        # Write JSON file to workspace (for GitLab artifacts)
        $jsonData | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile -Encoding UTF8
        Write-Status "Oracle database information written to: $jsonFile" "Success"
        
        # Copy to shared config directory
        Copy-Item -Path $jsonFile -Destination $sharedJsonFile -Force
        Write-Status "Copied to shared location: $sharedJsonFile" "Info"
        
    } catch {
        Write-Status "Failed to write JSON file: $($_.Exception.Message)" "Error"
    }
    
    exit 0
} else {
    Write-Status "No running Oracle databases found on this server" "Warning"
    exit 1
}
