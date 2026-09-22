# Trust.ps1

# Check if the root folder exists on drive D:
$rootFolderD = "D:\"
if (Test-Path $rootFolderD) {
    $rootFolder = $rootFolderD
}
else {
    # Check if the root folder exists on drive E:
    $rootFolderE = "E:\"
    if (Test-Path $rootFolderE) {
        $rootFolder = $rootFolderE
    }
    else {
        Write-Host "Error: Neither drive D nor E contains the required folder structure." -ForegroundColor Red
        exit 1  # Use a specific exit code to indicate an error
    }
}

# Define the root folder and construct paths
$caciFolder = Join-Path $rootFolder "CACI"
$dbTierFolder = Join-Path $caciFolder "DBTier"
$datamartFolder = Join-Path $dbTierFolder "Datamart"
$configFilePath = Join-Path $datamartFolder "config.bat"

# Define the log file path with a timestamp
$logFilePath = Join-Path $datamartFolder "Upgrade_Logs\Update_pg_hba_conf_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Redirect output to the log file
Start-Transcript -Path $logFilePath

try {
    $ErrorActionPreference = "Stop"
    # Read values from the batch file content and set variables
    $configContent = Get-Content -Path $configFilePath
    foreach ($line in $configContent) {
        if ($line -match '^set\s+(\w+)\s*=\s*"?(.*)"?$') {
            $key = $matches[1]
            $value = $matches[2] -replace '^"(.*)"$', '$1'
            Set-Variable -Name $key -Value $value
        }
    }

    # Define PostgreSQL data directory
    $postgresDataDirectory = $PGDATA

    # Define the path to pg_hba.conf
    $pgHbaConfigPath = Join-Path $postgresDataDirectory "pg_hba.conf"

    # Specify the authentication method you want to set
    $newAuthMethod = "trust"

    # Check if pg_hba.conf exists before making changes
    if (Test-Path $pgHbaConfigPath -PathType Leaf) {
        # Backup pg_hba.conf
        $backupPath = Join-Path $postgresDataDirectory "pg_hba_backup.conf"
        Copy-Item -Path $pgHbaConfigPath -Destination $backupPath -Force

        # Read the content of pg_hba.conf
        $pgHbaContent = Get-Content -Path $pgHbaConfigPath

        # Replace only the last token with 'trust', preserving original spacing
        $newPgHbaContent = $pgHbaContent | ForEach-Object {
            if ($_ -match '^\s*(host|local)\s+') {
                $_ -replace '(\S+)$', $newAuthMethod
            } else {
                $_
            }
        }

        # Write the updated content back to pg_hba.conf
        $newPgHbaContent | Set-Content -Path $pgHbaConfigPath

        Write-Host "Authentication method in pg_hba.conf updated to: $newAuthMethod for all entries." -ForegroundColor Green
        Write-Host "Backup created at: $backupPath" -ForegroundColor Green
        
        # Create text file that stores information about Trust.ps1 to indicate successful completion
        $successIndicatorFilePath = Join-Path $datamartFolder "Upgrade_Logs\Trust_Success.txt"
        New-Item -Path $successIndicatorFilePath -ItemType File -Force
        
    } else {
        Write-Host "Warning: pg_hba.conf not found. No changes were made." -ForegroundColor Red
    }
}
catch {
    # Log any errors to the transcript
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1  # Use a specific exit code to indicate an error
}
finally {
    # Stop transcript to close the log file
    Stop-Transcript
}
