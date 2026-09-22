
# Set the current directory to the script directory
Set-Location -Path $PSScriptRoot

$success = $true  # Initialize success flag

Write-Host "*******************************"
Write-Host "Running Script 1: Checks*"
Write-Host "*******************************"
powershell.exe -File "checks.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Checks failed. Stopping process." -ForegroundColor Red
    exit 1
}


if ($success) {
    Write-Host "*******************************"
    Write-Host "Running Script 2: Change trust*"
    Write-Host "*******************************"
    powershell.exe -File "Trust.ps1"
    if ($LASTEXITCODE -ne 0) {
        $success = $false
    }
}

if ($success) {
    Write-Host "*********************************************"
    Write-Host "Running Script 3: Refresh Schema*"
    Write-Host "*********************************************"
    powershell.exe -File "datamart_refresh.ps1"
    if ($LASTEXITCODE -ne 0) {
        $success = $false
    }
}

if ($success) {
    Write-Host "*************************************************"
    Write-Host "Running Script 4: Reverse changes to pg_hba.conf*"
    Write-Host "*************************************************"
    powershell.exe -File "TrustR.ps1"
    if ($LASTEXITCODE -ne 0) {
        $success = $false
    }
}

if ($success) {
    Write-Host "------------------------------------------------------------"
    Write-Host "-************ALL SCRIPTS EXECUTED SUCCESSFULLY.************-"
    Write-Host "-**PLEASE REFRESH DATA BY RUNNING DATAMART TASK SCHEDULED**-"
    Write-Host "------------------------------------------------------------"
} else {
    Write-Host "------------------------------------------------------------"
    Write-Host "-************SOME SCRIPTS FAILED. CHECK LOGS FOR DETAILS.************-"
    Write-Host "------------------------------------------------------------"
}

Read-Host "Press Enter to exit"
