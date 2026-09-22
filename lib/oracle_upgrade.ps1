# ChildView upgrade script - User modification strictly prohibited Copyright CACI Ltd

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
$global:package= Resolve-Path -Path "$basedir\package"
$global:log_path= Resolve-Path -Path "$basedir\logs"

# Get version details and settings
. $module_path\About.ps1

Get-Module | Remove-Module

Import-module $module_path\Logging
Import-module $module_path\oracle_tools
Import-module $module_path\oracle_select
Import-module $module_path\oracle_install_home
Import-module $module_path\oracle_upgrade_db
Import-module $module_path\oracle_upgrade_apex
Import-module $module_path\Folder-Ident
Import-module $module_path\caci_utils

$padLeft = 'test'.PadLeft(25)

$banner_width=55

write-host -f yellow -BackgroundColor Red "".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor Red "  ChildView Database Patch $cv_ver : $cv_cpu".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor Red "  ================================".PadRight($banner_width," ") 
write-host -f yellow -BackgroundColor Red "  It is critical a server backup has been performed".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor Red "  prior to running this upgrade.".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor Red "  Ensure all users are out of the system.".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor Red "  ===========================".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor blue "".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor blue "  This upgrade is the first of two main parts.".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor blue "  The ChildView system will be non-functional".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor blue "  until the ChildView $cv_ver application installer".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor blue "  has been run successfully.".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor blue "".PadRight($banner_width," ")




do {
    $confirmation = Read-Host "Please type CONFIRMED to proceed (ctrl/c to exit):"
    } while ($confirmation -ne 'CONFIRMED')

# Perform an MD5 check on any packages required
# Get-FileHash .\WINDOWS.X64_191500_db_home.zip -Algorithm MD5
# Update below file and md5 details, and oracle_db_pack constant in oracle_install_home.psm1

$md5List = @()
$md5List+=New-Object PsObject -property @{ name = "Database pack"; file = "WINDOWS.X64_192200_db_home.zip"; md5 = "EF9FC37171005E03FA8DF2986C7CE69C"; version = "19.22.0"; space=10399592448}

md5_file_check $md5List $package.path

# Use/Create the generated audit and select a database to process
LogWrite "Running $($MyInvocation.MyCommand.Name) Software Base directory : $basedir"
LogWrite "Parameters : $args"

LogWrite "ChildView Database Upgrade" -logout
LogWrite "=========================" -logout
LogWrite "Log path : $log_path" -logout
LogWrite "_________________________" -logout
LogWrite "Modules location - $module_path"
LogWrite "Resource location - $resource"
LogWrite "Modules loaded - Starting"

[hashtable]$db_details = @{}

# Choose a database
$discard = choose_db $db_details

# Check for Speech marks in the service executable
$check_service = (Get-CIMInstance -Class Win32_Service -Filter "name ='OracleService$($db_details.SID)' " | Select-Object PathName)
if ($check_service.pathname.contains('"')) {

    write-host -f yellow -BackgroundColor Red " Unable to upgrade the database:                         "
    write-host -f yellow -BackgroundColor Red " The Database service has speech marks in the executable "
    write-host -f yellow -BackgroundColor Red " Please update the service definition to remove          "
    write-host -f yellow -BackgroundColor Red " the speech marks, and re-run this upgrade               "
    

} else {


# Install Database home
$discard = oracle_install_new_home -db_details:$db_details -software_pack:$md5list

# Upgrade database
$discard = oracle_upgrade_db $db_details

# Upgrade database componenets
$discard = oracle_upgrade_apex $db_details

write-host -f yellow "                                                     " -BackgroundColor blue
write-host -f yellow "  The ChildView database has been successfully       " -BackgroundColor blue
write-host -f yellow "  Upgraded. It is recommended to perform a post      " -BackgroundColor blue
write-host -f yellow "  server backup to secure the database at this       " -BackgroundColor blue
write-host -f yellow "  stage, to avoid having to re-process the upgrade.  " -BackgroundColor blue
write-host -f yellow "                                                     " -BackgroundColor blue
write-host -f yellow "  Database Upgrade Completed.                        " -BackgroundColor blue
write-host -f yellow "                                                     " -BackgroundColor blue

}