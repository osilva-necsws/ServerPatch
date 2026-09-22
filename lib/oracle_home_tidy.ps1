# DB Home tidy script - User modification strictly prohibited Copyright CACI Ltd

# Check running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -eq $false) {
	write-host -f red '"Run as administrator" privilege is requried for this script'
	[void](Read-Host 'Press Enter to exit')
	exit
}
# Select database to OUpgrade
$database_id=$args[0]

$scriptdir = split-path $PSScriptRoot -leaf

if ($scriptdir="lib")
{
   $basedir = Resolve-Path -Path "$PSScriptRoot\.."
} else {
    $basedir = Resolve-Path -Path "$PSScriptRoot"
}

Push-Location $basedir

$global:basedir= Resolve-Path -Path "$basedir"
$global:module_path= Resolve-Path -Path "$basedir\lib"
$global:resource= Resolve-Path -Path "$basedir\resource"
$global:log_path= Resolve-Path -Path "$basedir\logs"

Get-Module | Remove-Module

Import-module $module_path\Logging
Import-module $module_path\oracle_tools


write-host -f yellow "                                                     " -BackgroundColor Red
write-host -f yellow "  ChildView Database Tidy                            " -BackgroundColor Red
write-host -f yellow "  =======================                            " -BackgroundColor Red
write-host -f yellow "  It is critical a server backup has been performed  " -BackgroundColor Red
write-host -f yellow "  prior to running this upgrade.                     " -BackgroundColor Red
write-host -f yellow "                                                     " -BackgroundColor blue
write-host -f yellow "  This script will remove unused database software   " -BackgroundColor blue
write-host -f yellow "  from the server. Checks are done against services  " -BackgroundColor blue
write-host -f yellow "  and the script will remove DB version that have no " -BackgroundColor blue
write-host -f yellow "  service(s)                                         " -BackgroundColor blue

do {
    $confirmation = Read-Host "Please type CONFIRMED to proceed (ctrl/c to exit):"
    } while ($confirmation -ne 'CONFIRMED')

$found_homes=db_homes_findall
$home_dets = db_service_findall $found_homes

foreach ($proc_home in $home_dets) 
{
    if ($proc_home.servcnt -gt 0) 
    {
        write-host "Home $($proc_home.home) has $($proc_home.servcnt) connected service(s)"
    }
    else
    {
        write-host "$($proc_home.home) - No services, Removing home"
        db_deinstall $proc_home.home
    }
}

