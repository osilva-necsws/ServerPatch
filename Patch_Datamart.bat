
@echo off
REM Command file to setup and execute Powershell script
powershell -ExecutionPolicy Bypass -File "%~dp0lib\datamart_update.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo Process failed. Stopping batch execution.
    exit /b 1
)
