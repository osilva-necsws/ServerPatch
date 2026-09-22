@echo off
REM Command file to setup and execute Powershell script
REM Pass database_id as first argument if provided
powershell -executionPolicy bypass -file lib/oracle_patch.ps1 %1
