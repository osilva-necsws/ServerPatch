# -------------------------------
# 1. Determine Root Folder
# -------------------------------
$rootFolder = if (Test-Path "D:\") { "D:\" } elseif (Test-Path "E:\") { "E:\" } else {
    Write-Host "Error: Neither drive D nor E contains the required folder structure." -ForegroundColor Red
    exit 1
}

# -------------------------------
# 2. Define Paths
# -------------------------------
$caciFolder = Join-Path $rootFolder "CACI"
$dbTierFolder = Join-Path $caciFolder "DBTier"
$datamartFolder = Join-Path $dbTierFolder "Datamart"
$configFilePath = Join-Path $datamartFolder "config.bat"
$generateFolderPath = Join-Path $datamartFolder "generate"
$generateBackupFolderPath = Join-Path $datamartFolder "generate_backup"
$deleteListPath = Join-Path $PSScriptRoot "delete.txt"
$pgGenerateScript = Join-Path $datamartFolder "pg_generate_table_list.bat"
$pgCreateScript = Join-Path $datamartFolder "pg_create_schema_run_script.bat"
$pgTableListPath = Join-Path $generateFolderPath "pg_table_list.bat"
$schemasFolderPath = Join-Path $generateFolderPath "schema"

# -------------------------------
# 3. Start Logging
# -------------------------------
$logFilePath = Join-Path $datamartFolder "Upgrade_Logs\Upgrade_Process_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $logFilePath

try {
    $ErrorActionPreference = "Stop"

    # -------------------------------
    # 4. Backup generate folder
    # -------------------------------
    if (Test-Path $generateBackupFolderPath) {
        Remove-Item -Path $generateBackupFolderPath -Recurse -Force
        Write-Host "Old generate_backup folder removed."
    }
    Copy-Item -Path $generateFolderPath -Destination $generateBackupFolderPath -Recurse
    Write-Host "generate folder backed up to generate_backup."

    # -------------------------------
    # 5. Change to Datamart directory
    # -------------------------------
    Set-Location -Path $datamartFolder

    # -------------------------------
    # 6. Parse config.bat and invoke it
    # -------------------------------
    if (Test-Path $configFilePath) {
        # Parse variables for PowerShell
        $configContent = Get-Content -Path $configFilePath
        foreach ($line in $configContent) {
            if ($line -match '^set\s+(\w+)\s*=\s*"?(.*)"?$') {
                $key = $matches[1]
                $value = $matches[2] -replace '^"(.*)"$', '$1'
                Set-Variable -Name $key -Value $value
            }
        }

        # Invoke config.bat for CMD environment changes
        Invoke-Expression -Command "cmd /c `"$configFilePath`""
        Write-Host "config.bat executed successfully."
    } else {
        throw "config.bat not found at $configFilePath"
    }

    if (-not $PGPATH) { throw "PGPATH not set in config.bat." }
    $psqlPath = Join-Path $PGPATH "psql.exe"

    # -------------------------------
    # 7. Run pg_generate_table_list.bat
    # -------------------------------
    if (Test-Path $pgGenerateScript) {
        & $pgGenerateScript
        Write-Host "pg_generate_table_list.bat executed."
    } else {
        throw "pg_generate_table_list.bat not found."
    }

    # -------------------------------
    # 8. Clean pg_table_list.bat using delete.txt
    # -------------------------------
    if (-not (Test-Path $deleteListPath)) { throw "delete.txt not found." }
    if (-not (Test-Path $pgTableListPath)) { throw "pg_table_list.bat not found." }

    $tablesToDelete = Get-Content $deleteListPath | ForEach-Object { $_.Trim().Trim("'") } | Where-Object { $_ -ne "" }
    $tableListLines = Get-Content $pgTableListPath
    $filteredLines = foreach ($line in $tableListLines) {
        if (-not ($tablesToDelete | Where-Object { $line -like "*CALL pg_generate_schema_from_oracle.bat $_*" })) {
            $line
        }
    }
    $filteredLines | Set-Content $pgTableListPath
    Write-Host "pg_table_list.bat cleaned using delete.txt."

    # -------------------------------
    # 9. Ensure schemas folder exists and clear it
    # -------------------------------
    if (-not (Test-Path $schemasFolderPath)) {
        New-Item -ItemType Directory -Path $schemasFolderPath | Out-Null
        Write-Host "schemas folder created."
    } else {
        Remove-Item -Path $schemasFolderPath\* -Recurse -Force
        Write-Host "schemas folder cleared."
    }

    # -------------------------------
    # 10. Run pg_table_list.bat to populate schemas
    # -------------------------------
    & $pgTableListPath
    Write-Host "pg_table_list.bat executed to populate schemas folder."

    # -------------------------------
    # 11. Run pg_create_schema_run_script.bat
    # -------------------------------
    if (Test-Path $pgCreateScript) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$pgCreateScript`"" -Wait
        Write-Host "pg_create_schema_run_script.bat executed."
    } else {
        throw "pg_create_schema_run_script.bat not found."
    }
# -------------------------------
	Set-Location -Path $datamartFolder
	
	# -------------------------------
    # . Parse config.bat and invoke it
    # -------------------------------
    if (Test-Path $configFilePath) {
        # Parse variables for PowerShell
        $configContent = Get-Content -Path $configFilePath
        foreach ($line in $configContent) {
            if ($line -match '^set\s+(\w+)\s*=\s*"?(.*)"?$') {
                $key = $matches[1]
                $value = $matches[2] -replace '^"(.*)"$', '$1'
                Set-Variable -Name $key -Value $value
            }
        }

        # Invoke config.bat for CMD environment changes
        Invoke-Expression -Command "cmd /c `"$configFilePath`""
        Write-Host "config.bat executed successfully."
    } else {
        throw "config.bat not found at $configFilePath"
    }

    if (-not $PGPATH) { throw "PGPATH not set in config.bat." }
    $psqlPath = Join-Path $PGPATH "psql.exe"

# -------------------------------	
    # -------------------------------
    # 12. Run Create_schema.psql (relative path)
    # -------------------------------
    Write-Host "Executing Create_schema.psql from Datamart directory..." -ForegroundColor Cyan
    & $psqlPath -U cvdm_sqlwb -d cv_datamart -f "generate\schema\Create_schema.psql"
    Write-Host "Create_schema.psql executed successfully."

    # -------------------------------
    # 13. PostgreSQL Grants
    # -------------------------------
    $psqlCommands = @"
grant all on database cv_datamart to cvdm_admin;
grant all on schema cvmviews to cvdm_admin;
grant connect on database cv_datamart to cvdm_user;
grant usage on schema cvmviews to cvdm_user;
grant select on all tables in schema cvmviews to cvdm_user;
"@
    & $psqlPath -U postgres -d cv_datamart -c $psqlCommands
    Write-Host "PostgreSQL schema and grants applied successfully."

    # -------------------------------
    # 14. Success Marker
    # -------------------------------
    $successIndicatorFilePath = Join-Path $datamartFolder "Upgrade_Logs\Upgrade_Success.txt"
    "Upgrade completed successfully on $(Get-Date)" | Set-Content $successIndicatorFilePath -Force
    Write-Host "Upgrade process completed successfully." -ForegroundColor Green

} catch {
    Write-Host "Error occurred: $_" -ForegroundColor Red
    exit 1
} finally {
    Stop-Transcript
}
