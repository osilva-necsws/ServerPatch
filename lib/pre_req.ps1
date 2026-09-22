. .\logging.ps1


$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Push-Location $dir

# Constants
$Logfile = "install_$(get-date -f dd-MM-yyyy_HH_mm).log"

# Identify logfile location
# If running in a non-standard location, defaults to the same directory


LogWrite "Powershell Pre-requisites check : $($PSScriptInfo.VERSION)"

# Check running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -eq $false) {
	write-host -f red '"Run as administrator" privilege is requried for this script'
	[void](Read-Host 'Press Enter to exit')
	exit
}

# Check Powershell version
Logwrite "Checking powershell version : v$($PSVersionTable.PSVersion.Major)"
if ($PSVersionTable.PSVersion.Major -eq $null -or $PSVersionTable.PSVersion.Major -lt 4) {
	write-host -f red 'PowerShell v4 or greater is required to execute this script'
    Logwrite "Expecting powershell v4 or later, found v$($PSVersionTable.PSVersion.Major) : Exiting"
	[void](Read-Host 'Press Enter to exit')
	exit
}
