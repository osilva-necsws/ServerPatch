# ChildView utility script - User modification strictly prohibited Copyright CACI Ltd

# Check running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -eq $false) {
	write-host -f red '"Run as administrator" privilege is requried for this script'
	[void](Read-Host 'Press Enter to exit')
	exit
}

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
$global:log_path= Resolve-Path -Path "$basedir\logs"

Get-Module | Remove-Module

Import-module $module_path\Logging
Import-module $module_path\caci_utils

write-host -f yellow "                                                     " -BackgroundColor Red
write-host -f yellow "  ChildView Utilities - Log4J removal                " -BackgroundColor Red
write-host -f yellow "  ===================================                " -BackgroundColor Red
write-host -f yellow "  Please ensure a server backup has been performed   " -BackgroundColor Red
write-host -f yellow "  or a rollback solution is available prior to       " -BackgroundColor Red
write-host -f yellow "  running this script.                               " -BackgroundColor Red
write-host -f yellow "                                                     " -BackgroundColor Red

do {
    $confirmation = Read-Host "Please type CONFIRMED to proceed (ctrl/c to exit):"
    } while ($confirmation -ne 'CONFIRMED')

# Log sciript details
LogWrite "Running $($MyInvocation.MyCommand.Name) Software Base directory : $basedir"
LogWrite "Parameters : $args"

# Folder identifier
$search_folder="CACI"
# Exclusion filter
#$exclude_filter='*tomcat*\*\*webapps*'
$exclude_filter='NOT IN USE'

# Find CACI Software installations
$install_drives = find_installation_roots $search_folder

foreach ($install_drive in $install_drives){
    $installation = Resolve-Path -Path "$($install_drive.DeviceID)\$search_folder"
    $file_list = install_find_files $installation "log4j-*-2*.jar"
    foreach ($excl in ($file_list | Where-Object { $_.Fullname -like "$exclude_filter" })) {
        LogWrite "    Excluding : $($excl.Fullname)" -loginfo
    }
    $remove_list = $file_list | Where-Object { $_.Fullname -notlike "$exclude_filter" }
    if ($remove_list.count -eq 0) {
        LogWrite "No files found for removal in $installation" -loginfo -logout
    } else {
        LogWrite "Found $($remove_list.count) files in $installation" -logwarn -logout
        remove_files $remove_list
        LogWrite "Remove completed in $installation" -loginfo -logout
    }
}


