# -------------------------------
# Administrator Privilege Check
# -------------------------------
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -eq $false) {
    Write-Host -ForegroundColor Red '"Run as administrator" privilege is required for this script.'
    [void](Read-Host 'Press Enter to exit')
    exit 1
}

# -------------------------------
# 1. Check for PostgreSQL
# -------------------------------
function Test-PostgreSQLInstalled {
    $pgService = Get-Service -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like "postgresql*" -or $_.Name -eq "ChildView_PostgreSQL"
    }
    if ($pgService | Where-Object { $_.Status -eq 'Running' }) {
        Write-Host "PostgreSQL service is running: $($pgService.Name)" -ForegroundColor Green
        return $true
    }
    if (Get-Command psql.exe -ErrorAction SilentlyContinue) {
        Write-Host "Found psql.exe in PATH." -ForegroundColor Green
        return $true
    }
    return $false
}

if (-not (Test-PostgreSQLInstalled)) {
    Write-Host "Error: PostgreSQL is not installed or running." -ForegroundColor Red
    exit 1
}


# -------------------------------
# 2. Check for Amazon Corretto and Install if Missing
# -------------------------------
function Install-AmazonCorretto {
    $msiPath = Join-Path (Split-Path $PSScriptRoot -Parent) "package\amazon-corretto-8.462.08.1-windows-x64-jre.msi"
    if (Test-Path $msiPath) {
        Write-Host "Installing Amazon Corretto from $msiPath..." -ForegroundColor Yellow
        $installArgs = "/i `"$msiPath`" /quiet /norestart"
        $process = Start-Process "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Host "Amazon Corretto installation completed successfully." -ForegroundColor Green
            return $true
        } else {
            Write-Host "Amazon Corretto installation failed with exit code $($process.ExitCode)." -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host "Error: MSI file not found at $msiPath." -ForegroundColor Red
        return $false
    }
}

function Test-AmazonCorrettoInstalled {
    if ($env:JAVA_HOME -and $env:JAVA_HOME -like "*corretto*") {
        Write-Host "Amazon Corretto found via JAVA_HOME: $env:JAVA_HOME" -ForegroundColor Green
        return $true
    }
    try {
        $javaVersion = & java -version 2>&1
        if ($javaVersion -match "Corretto") {
            Write-Host "Amazon Corretto detected via java -version." -ForegroundColor Green
            return $true
        }
    } catch {
        # java not found
    }
    $paths = @(
        "C:\Program Files\Amazon Corretto",
        "C:\Program Files (x86)\Amazon Corretto"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) {
            Write-Host "Amazon Corretto found at: $path" -ForegroundColor Green
            return $true
        }
    }
    return $false
}

# Check and install if missing
if (-not (Test-AmazonCorrettoInstalled)) {
    Write-Host "Amazon Corretto JDK is not installed. Attempting installation..." -ForegroundColor Yellow
    if (-not (Install-AmazonCorretto)) {
        Write-Host "Error: Amazon Corretto installation failed." -ForegroundColor Red
        exit 1
    }
}

