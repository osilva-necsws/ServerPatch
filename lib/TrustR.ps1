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


# Check if Trust.ps1 completed successfully by checking the existence of the success indicator file
$successIndicatorFilePath = Join-Path $datamartFolder "Upgrade_Logs\Trust_Success.txt"

if (Test-Path $successIndicatorFilePath) {
    # Continue with TrustR.ps1 actions

    # Define the log file path with a timestamp
    $logFilePath = Join-Path $datamartFolder "Upgrade_Logs\Trust_reverse_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # Redirect output to the log file
    Start-Transcript -Path $logFilePath

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

    # Define the path to pg_hba.conf and backup file
    $pgHbaConfigPath = Join-Path $postgresDataDirectory "pg_hba.conf"
    $backupPath = Join-Path $postgresDataDirectory "pg_hba_backup.conf"

    # Check if the backup file exists
    if (Test-Path $backupPath) {
        # Copy the content from backup to pg_hba.conf
        Copy-Item -Path $backupPath -Destination $pgHbaConfigPath -Force

        # Display a message indicating the restore
        Write-Host "Restored original pg_hba.conf from backup." -ForegroundColor Green

        # Remove the backup file
        Remove-Item -Path $backupPath -Force
        Write-Host "Backup file removed: $backupPath" -ForegroundColor Green
    } else {
        Write-Host "Error: Backup file not found. Cannot restore." -ForegroundColor Red
    }

    # Stop transcript to close the log file
    Stop-Transcript
    # Remove the success indicator file
    Remove-Item -Path $successIndicatorFilePath -Force
}
else {
    Write-Host "Error: Trust.ps1 did not complete successfully. TrustR.ps1 will not proceed." -ForegroundColor Red
    exit 1  # Use a specific exit code to indicate an error
}