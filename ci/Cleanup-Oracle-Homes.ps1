# Cleanup Unused Oracle Homes
# Automatically deinstalls Oracle homes that are no longer in use

param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Oracle Home Cleanup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if markers exist indicating earlier failures
if (Test-Path "artifacts/no_databases_found.marker") {
    Write-Host "⚠ No Oracle databases found on server - skipping cleanup" -ForegroundColor Yellow
    exit 0
}

# Read the database details from the JSON artifact for server name
$jsonPath = "artifacts/oracle_databases.json"
if (-not (Test-Path $jsonPath)) {
    Write-Host "❌ ERROR: Database JSON file not found at $jsonPath" -ForegroundColor Red
    exit 1
}

$dbInfo = Get-Content $jsonPath -Raw | ConvertFrom-Json

Write-Host "Server: $($dbInfo.ServerName)" -ForegroundColor Cyan
Write-Host ""

# Rescan for current Oracle databases (in case changes occurred during pipeline)
Write-Host "Rescanning for current Oracle database instances..." -ForegroundColor Cyan

$databases = @()
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
                # Try service path
            }
        }
        
        # If not found in registry, try to get it from service ImagePath
        if (-not $oracleHome) {
            try {
                $servicePath = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$($service.Name)'" -ErrorAction SilentlyContinue).PathName
                if ($servicePath -and $servicePath -match '(.+?)\\bin\\') {
                    $oracleHome = $matches[1].Trim('"')
                }
            } catch {
                # Continue
            }
        }
        
        $databases += [PSCustomObject]@{
            SID = $sid
            ServiceName = $service.Name
            Status = $service.Status
            StartType = $service.StartType
            OracleHome = $oracleHome
        }
    }
}

Write-Host "✓ Found $($databases.Count) running database(s)" -ForegroundColor Green
foreach ($db in $databases) {
    Write-Host "  - SID: $($db.SID), Status: $($db.Status), Home: $($db.OracleHome)" -ForegroundColor White
}
Write-Host ""

# Rescan for all Oracle Homes from registry
Write-Host "Rescanning for Oracle homes..." -ForegroundColor Cyan

$allOracleHomes = @()
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
                if ($oracleHome -and (Test-Path $oracleHome) -and $allOracleHomes -notcontains $oracleHome) {
                    $allOracleHomes += $oracleHome
                }
            }
        } catch {
            # Continue
        }
    }
}

Write-Host "✓ Found $($allOracleHomes.Count) Oracle home(s)" -ForegroundColor Green
foreach ($homePath in $allOracleHomes) {
    Write-Host "  - $homePath" -ForegroundColor White
}
Write-Host ""

# Get list of Oracle homes currently in use by databases
$inUseHomes = @()
foreach ($db in $databases) {
    if ($db.OracleHome -and $inUseHomes -notcontains $db.OracleHome) {
        $inUseHomes += $db.OracleHome
        Write-Host "  Database $($db.SID) using: $($db.OracleHome)" -ForegroundColor Gray
    }
}

# Check for Oracle homes used by listeners
Write-Host ""
Write-Host "Checking for Oracle Listeners..." -ForegroundColor Cyan

$listenerServices = Get-Service -ErrorAction SilentlyContinue | Where-Object { 
    $_.Name -like "OracleOraHome*TNSListener*" -or
    $_.Name -like "Oracle*Listener*" -or
    $_.DisplayName -like "*TNS Listener*"
}

if ($listenerServices) {
    Write-Host "Found $($listenerServices.Count) Oracle listener service(s)" -ForegroundColor Cyan
    
    foreach ($listener in $listenerServices) {
        # Try to extract Oracle Home from service path
        try {
            $servicePath = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$($listener.Name)'" -ErrorAction SilentlyContinue).PathName
            
            if ($servicePath) {
                # Extract path from service executable (typically ORACLE_HOME\bin\tnslsnr.exe)
                if ($servicePath -match '(.+?)\\bin\\') {
                    $listenerHome = $matches[1].Trim('"')
                    
                    if ($listenerHome -and $inUseHomes -notcontains $listenerHome) {
                        $inUseHomes += $listenerHome
                        Write-Host "  Listener $($listener.Name) using: $listenerHome" -ForegroundColor Gray
                    }
                }
            }
        } catch {
            # Silently continue if unable to determine listener home
        }
    }
} else {
    Write-Host "No Oracle listener services found" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Oracle Homes in use (databases + listeners):" -ForegroundColor Green
foreach ($oracleHomePath in $inUseHomes) {
    Write-Host "  ✓ $oracleHomePath" -ForegroundColor Green
}
Write-Host ""

# Identify unused Oracle homes (database homes only, exclude client installations)
$unusedHomes = @()
foreach ($oracleHomePath in $allOracleHomes) {
    $isInUse = $false
    foreach ($usedHome in $inUseHomes) {
        if ($oracleHomePath -eq $usedHome) {
            $isInUse = $true
            break
        }
    }
    
    # Only include database homes (exclude ODAC and client installations)
    $isClientHome = $oracleHomePath -match 'ODAC|client_1|client'
    
    if (-not $isInUse -and -not $isClientHome) {
        # Verify it's a database home by checking for dbhome_ pattern or database files
        if ($oracleHomePath -match 'dbhome_\d+' -or (Test-Path (Join-Path $oracleHomePath "bin\oracle.exe"))) {
            $unusedHomes += $oracleHomePath
        } else {
            Write-Host "Skipping non-database home: $oracleHomePath" -ForegroundColor Gray
        }
    } elseif ($isClientHome) {
        Write-Host "Skipping client home: $oracleHomePath" -ForegroundColor Gray
    }
}

if ($unusedHomes.Count -eq 0) {
    Write-Host "✓ No unused database homes found - all homes are in use" -ForegroundColor Green
    Write-Host ""
    exit 0
}

Write-Host "Unused Database Homes to deinstall:" -ForegroundColor Yellow
foreach ($oracleHomePath in $unusedHomes) {
    Write-Host "  ⚠ $oracleHomePath" -ForegroundColor Yellow
}
Write-Host ""

# Deinstall each unused Oracle home
$cleanupResults = @()

foreach ($unusedHome in $unusedHomes) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Deinstalling: $unusedHome" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Check if deinstall utility exists
    $deinstallPath = Join-Path $unusedHome "deinstall\deinstall.bat"
    
    if (-not (Test-Path $deinstallPath)) {
        Write-Host "⚠ WARNING: deinstall.bat not found at $deinstallPath" -ForegroundColor Yellow
        Write-Host "Skipping this Oracle home" -ForegroundColor Yellow
        $cleanupResults += @{
            OracleHome = $unusedHome
            Status = "SKIPPED"
            Reason = "Deinstall utility not found"
        }
        Write-Host ""
        continue
    }
    
    # Create response file for silent deinstallation
    $responseFileContent = @"
ORACLE_HOME=$unusedHome
INVENTORY_LOCATION=C:\Program Files\Oracle\Inventory
REMOVE_HOMES=$unusedHome
"@
    
    $responseFile = Join-Path $env:TEMP "deinstall_response_$([guid]::NewGuid().ToString()).rsp"
    $responseFileContent | Out-File -FilePath $responseFile -Encoding ASCII -Force
    
    Write-Host "Running deinstall in silent mode..." -ForegroundColor Cyan
    Write-Host "Response file: $responseFile" -ForegroundColor Gray
    Write-Host ""
    
    try {
        # Run deinstall with silent mode and response file (no -checkonly to perform actual deinstall)
        $deinstallArgs = @(
            "-silent",
            "-paramfile",
            "`"$responseFile`""
        )
        
        Write-Host "Executing: $deinstallPath $($deinstallArgs -join ' ')" -ForegroundColor Gray
        
        # Execute deinstall and capture output
        $process = Start-Process -FilePath $deinstallPath -ArgumentList $deinstallArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\deinstall_stdout.log" -RedirectStandardError "$env:TEMP\deinstall_stderr.log"
        
        $exitCode = $process.ExitCode
        
        # Read output logs
        $stdout = if (Test-Path "$env:TEMP\deinstall_stdout.log") { Get-Content "$env:TEMP\deinstall_stdout.log" -Raw } else { "" }
        $stderr = if (Test-Path "$env:TEMP\deinstall_stderr.log") { Get-Content "$env:TEMP\deinstall_stderr.log" -Raw } else { "" }
        
        Write-Host "Exit Code: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Yellow" })
        
        if ($stdout) {
            Write-Host "Standard Output:" -ForegroundColor Gray
            Write-Host $stdout -ForegroundColor Gray
        }
        
        if ($stderr) {
            Write-Host "Standard Error:" -ForegroundColor Yellow
            Write-Host $stderr -ForegroundColor Yellow
        }
        
        # Clean up logs
        Remove-Item "$env:TEMP\deinstall_stdout.log" -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:TEMP\deinstall_stderr.log" -Force -ErrorAction SilentlyContinue
        
        Write-Host ""
        Write-Host "Verifying Oracle Home removal..." -ForegroundColor Cyan
        
        # Clean up Oracle Inventory
        Write-Host "Cleaning Oracle Inventory..." -ForegroundColor Cyan
        $inventoryLocations = @(
            "C:\Program Files\Oracle\Inventory\ContentsXML\inventory.xml",
            "C:\Program Files (x86)\Oracle\Inventory\ContentsXML\inventory.xml"
        )
        
        foreach ($invPath in $inventoryLocations) {
            if (Test-Path $invPath) {
                try {
                    [xml]$inventory = Get-Content $invPath
                    $homeNodes = $inventory.INVENTORY.HOME_LIST.HOME | Where-Object { $_.LOC -eq $unusedHome }
                    
                    if ($homeNodes) {
                        Write-Host "  Found Oracle Home in inventory: $invPath" -ForegroundColor Gray
                        foreach ($node in $homeNodes) {
                            $node.ParentNode.RemoveChild($node) | Out-Null
                        }
                        $inventory.Save($invPath)
                        Write-Host "  ✓ Removed Oracle Home from inventory" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "  ⚠ Could not update inventory: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
        
        # Clean up Registry entries
        Write-Host "Cleaning Registry entries..." -ForegroundColor Cyan
        $registryPaths = @(
            "HKLM:\SOFTWARE\ORACLE",
            "HKLM:\SOFTWARE\WOW6432Node\ORACLE"
        )
        
        foreach ($regPath in $registryPaths) {
            if (Test-Path $regPath) {
                try {
                    $keys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
                    
                    foreach ($key in $keys) {
                        try {
                            $oracleHome = (Get-ItemProperty -Path $key.PSPath -Name "ORACLE_HOME" -ErrorAction SilentlyContinue).ORACLE_HOME
                            
                            if ($oracleHome -and $oracleHome -eq $unusedHome) {
                                Write-Host "  Found registry key for Oracle Home: $($key.PSChildName)" -ForegroundColor Gray
                                Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction Stop
                                Write-Host "  ✓ Removed registry key: $($key.PSChildName)" -ForegroundColor Green
                            }
                        } catch {
                            Write-Host "  ⚠ Could not remove registry key $($key.PSChildName): $($_.Exception.Message)" -ForegroundColor Yellow
                        }
                    }
                } catch {
                    Write-Host "  ⚠ Error accessing registry: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
        
        # Check if Oracle Home directory still exists
        if (Test-Path $unusedHome) {
            Write-Host "⚠ Oracle Home directory still exists after deinstall" -ForegroundColor Yellow
            Write-Host "Attempting manual removal of: $unusedHome" -ForegroundColor Yellow
            
            # Try multiple passes to delete as much as possible
            $maxAttempts = 3
            $deletedItems = 0
            $failedItems = 0
            
            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                Write-Host "  Removal attempt $attempt of $maxAttempts..." -ForegroundColor Gray
                
                try {
                    # Get all items recursively and delete from bottom up (files first, then directories)
                    $items = Get-ChildItem -Path $unusedHome -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object FullName -Descending
                    
                    foreach ($item in $items) {
                        try {
                            if ($item.PSIsContainer) {
                                # Try to remove directory
                                Remove-Item -Path $item.FullName -Force -ErrorAction Stop
                                $deletedItems++
                            } else {
                                # Try to remove file (with attributes reset)
                                $item.Attributes = 'Normal'
                                Remove-Item -Path $item.FullName -Force -ErrorAction Stop
                                $deletedItems++
                            }
                        } catch {
                            $failedItems++
                            # Silently continue - will try again on next pass
                        }
                    }
                    
                    # Try to remove the root directory
                    Remove-Item -Path $unusedHome -Force -ErrorAction Stop
                    $deletedItems++
                    break
                    
                } catch {
                    # Continue to next attempt
                    if ($attempt -lt $maxAttempts) {
                        Start-Sleep -Seconds 2
                    }
                }
            }
            
            Write-Host "  Deleted $deletedItems items" -ForegroundColor Gray
            if ($failedItems -gt 0) {
                Write-Host "  Failed to delete $failedItems items (may be in use or locked)" -ForegroundColor Yellow
            }
            
            # Final check
            if (-not (Test-Path $unusedHome)) {
                Write-Host "✓ Oracle Home directory successfully removed" -ForegroundColor Green
                $removalStatus = "Manually removed after deinstall ($deletedItems items deleted)"
            } else {
                # Check how much is left
                $remainingItems = (Get-ChildItem -Path $unusedHome -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
                
                if ($remainingItems -eq 0) {
                    # Empty directory remains - try once more
                    try {
                        Remove-Item -Path $unusedHome -Force -ErrorAction Stop
                        Write-Host "✓ Oracle Home directory successfully removed" -ForegroundColor Green
                        $removalStatus = "Manually removed after deinstall ($deletedItems items deleted)"
                    } catch {
                        Write-Host "⚠ WARNING: Empty Oracle Home directory could not be removed" -ForegroundColor Yellow
                        $removalStatus = "Partial removal - empty directory remains ($deletedItems items deleted, $failedItems failed)"
                    }
                } else {
                    Write-Host "⚠ WARNING: Could not fully remove Oracle Home directory ($remainingItems items remaining)" -ForegroundColor Yellow
                    $removalStatus = "Partial removal - $remainingItems items remaining ($deletedItems deleted, $failedItems failed)"
                }
            }
        } else {
            Write-Host "✓ Oracle Home directory successfully removed by deinstall" -ForegroundColor Green
            $removalStatus = "Removed by deinstall utility"
        }
        
        if ($exitCode -eq 0 -and -not (Test-Path $unusedHome)) {
            Write-Host "✓ Deinstall and cleanup completed successfully" -ForegroundColor Green
            $cleanupResults += @{
                OracleHome = $unusedHome
                Status = "SUCCESS"
                ExitCode = $exitCode
                RemovalStatus = $removalStatus
            }
        } else {
            Write-Host "⚠ Deinstall completed with warnings" -ForegroundColor Yellow
            $cleanupResults += @{
                OracleHome = $unusedHome
                Status = "WARNING"
                ExitCode = $exitCode
                RemovalStatus = $removalStatus
            }
        }
        
    } catch {
        Write-Host "✗ ERROR: Deinstall failed: $($_.Exception.Message)" -ForegroundColor Red
        $cleanupResults += @{
            OracleHome = $unusedHome
            Status = "FAILED"
            Error = $_.Exception.Message
        }
    } finally {
        # Clean up response file
        Remove-Item $responseFile -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host ""
}

# Generate cleanup summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Cleanup Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$successCount = ($cleanupResults | Where-Object { $_.Status -eq "SUCCESS" }).Count
$warningCount = ($cleanupResults | Where-Object { $_.Status -eq "WARNING" }).Count
$failedCount = ($cleanupResults | Where-Object { $_.Status -eq "FAILED" }).Count
$skippedCount = ($cleanupResults | Where-Object { $_.Status -eq "SKIPPED" }).Count

Write-Host "Total unused homes: $($unusedHomes.Count)" -ForegroundColor White
Write-Host "  ✓ Successfully deinstalled: $successCount" -ForegroundColor Green
Write-Host "  ⚠ Completed with warnings: $warningCount" -ForegroundColor Yellow
Write-Host "  ✗ Failed: $failedCount" -ForegroundColor Red
Write-Host "  ⊘ Skipped: $skippedCount" -ForegroundColor Gray
Write-Host ""

foreach ($result in $cleanupResults) {
    $statusColor = switch ($result.Status) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "FAILED" { "Red" }
        "SKIPPED" { "Gray" }
    }
    Write-Host "$($result.Status): $($result.OracleHome)" -ForegroundColor $statusColor
}

# Create cleanup report artifact
$cleanupReport = @{
    ServerName = $dbInfo.ServerName
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    TotalUnusedHomes = $unusedHomes.Count
    SuccessCount = $successCount
    WarningCount = $warningCount
    FailedCount = $failedCount
    SkippedCount = $skippedCount
    Results = $cleanupResults
}

$reportPath = "artifacts/oracle_cleanup.json"
$cleanupReport | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8 -Force

Write-Host ""
Write-Host "Cleanup report saved to: $reportPath" -ForegroundColor Cyan

# Exit with success if all deinstalls succeeded or had warnings only
if ($failedCount -eq 0) {
    Write-Host ""
    Write-Host "✓ Oracle home cleanup completed successfully" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "⚠ Oracle home cleanup completed with errors" -ForegroundColor Yellow
    exit 0  # Don't fail the pipeline, just report
}
