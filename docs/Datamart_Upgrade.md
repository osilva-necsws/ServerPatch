# Datamart Upgrade Process – Documentation


## 📌 Purpose

To streamline and automate the upgrade of a PostgreSQL Datamart environment by:
- Validating prerequisites
- Temporarily modifying authentication for seamless access
- Refreshing schemas and applying grants
- Logging all actions and marking success/failure
- A text file is placed inside the lib folder with all the tables that have to be deleted from cvmviews before the schema is updated.(This file can be edited to add or delete tables) 

---

## 🛠 Prerequisites

- Windows OS with PowerShell
- Administrator privileges
- PostgreSQL installed and running
- Amazon Corretto JDK MSI available at:
  packages\amazon-corretto-8.462.08.1-windows-x64-jre.msi
- Folder structure must exist under:
  D:\CACI\DBTier\Datamart
  or
  E:\CACI\DBTier\Datamart
- Required files:
  - config.bat- NEEDS TO BE UPDATED IF POSTGRES VERSION CHANGES
  - pg_generate_table_list.bat
  - pg_create_schema_run_script.bat
  - Create_schema.psql
  - delete.txt

---

## 📁 Script Overview

### 1. checks.ps1
- Verifies administrator privileges
- Checks PostgreSQL service and psql.exe
- Installs Amazon Corretto if missing.
- If new version of Amazon Corretto requires to be installed, we need to change the name of the file this part of the function:
    ```function Install-AmazonCorretto {
    $msiPath = Join-Path (Split-Path $PSScriptRoot -Parent) "packages\\amazon-corretto-8.462.08.1-windows-x64-jre.msi"
     ```
### 2. Trust.ps1
- Backs up pg_hba.conf
- Replaces authentication method with trust
- Logs changes and creates a success marker

### 3. datamart_refresh.ps1
- Parses config.bat for environment variables
- Executes schema generation and cleanup
- Applies PostgreSQL grants
- Logs all actions and creates a success marker

### 4. TrustR.ps1
- Restores original pg_hba.conf from backup

### 5. datamart_update.ps1
- Orchestrates execution of all scripts
- Stops if any script fails
- Displays final success or failure message

### 6. run_update.bat
Batch wrapper to launch the PowerShell orchestrator:
@echo off
REM Command file to setup and execute Powershell script
powershell -ExecutionPolicy Bypass -File "%~dp0lib\datamart_update.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo Process failed. Stopping batch execution.
    exit /b 1
)

---

## ⚠️ Error Handling

- Each script uses try/catch blocks to capture and log errors.
- Errors are written to timestamped log files in:
  Datamart\Upgrade_Logs\
- If any script fails, execution halts and a failure message is displayed.

---

## 🔄 Rollback Logic

- Trust.ps1 creates a backup of pg_hba.conf before modifying it.
- TrustR.ps1 restore the original pg_hba.conf from backup.
- datamart_refresh.ps1 backs up the generate folder before making changes.
- Success marker files (*_Success.txt) are created to track completed steps.

---

## ✅ Execution Order

1. run_update.bat → launches
2. datamart_update.ps1 → orchestrates
3. checks.ps1 → verifies environment
4. Trust.ps1 → sets trust authentication
5. datamart_refresh.ps1 → refreshes schema
6. TrustR.ps1 → restores authentication

---

## 📂 Output

- Log files with timestamps
- Updated schema in PostgreSQL
- Success indicators for audit and validation

---

## 🧩 Troubleshooting

- Check logs in Upgrade_Logs for details
- Ensure all required files and folders exist
- Verify PostgreSQL and Java installations