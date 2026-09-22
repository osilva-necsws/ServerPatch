# Postgres upgrade script - User modification strictly prohibited Copyright CACI Ltd

# Check running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -eq $false) {
	write-host -f red '"Run as administrator" privilege is requried for this script'
	[void](Read-Host 'Press Enter to exit')
	exit
}
# Select installation to Upgrade
$service_id=$args[0]

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

$global:save_path=$env:PATH

Get-Module | Remove-Module

Import-module $module_path\Logging
Import-module $module_path\postgres_tools
Import-module $module_path\caci_utils

write-host -f yellow "                                                     " -BackgroundColor Red
write-host -f yellow "  Postgres Database Upgrade                          " -BackgroundColor Red
write-host -f yellow "  ==========================                         " -BackgroundColor Red
write-host -f yellow "  It is critical a server backup has been performed  " -BackgroundColor Red
write-host -f yellow "  prior to running this upgrade.                     " -BackgroundColor Red
write-host -f yellow "  Ensure all users are out of the system.            " -BackgroundColor Red
write-host -f yellow "                                                     " -BackgroundColor Red


do {
    $confirmation = Read-Host "Please type CONFIRMED to proceed (ctrl/c to exit):"
    } while ($confirmation -ne 'CONFIRMED')





LogWrite "Running $($MyInvocation.MyCommand.Name) Software Base directory : $basedir"
LogWrite "Parameters : $args"

# Perform an MD5 check on any packages required
$md5list = Import-Clixml -Path "$($package.path)\pack_postgres_home.xml"

md5_file_check $md5List $package.path


LogWrite "Postgres Database Upgrade" -logout
LogWrite "=========================" -logout
LogWrite "Log path : $log_path" -logout
LogWrite "_________________________" -logout
LogWrite "Modules location - $module_path"
LogWrite "Resource location - $resource"
LogWrite "Modules loaded - Starting"


$pg_old_home=postgres_home
stop_postgres_deps
$pg_dumpfile=postgres_dumpall
LogWrite "check postgres dumpfile $pg_dumpfile" -logwarn -logout
if ($pg_dumpfile -eq 'ERROR'){
    LogWrite "Error occured during backup - aborting" -logwarn -logout
} else {
    # Install the newer Postgres software in the same base.
    # Unless one of the other options below are uncommented, and the original one commented out, which installs into ?:\CACI\DBTier\Postgres
    # excludes the C drive by default. To include, comment out the one with -include_c.

    # $pg_home=postgres_install -new_install
    # $pg_home=postgres_install -new_install -include_c

    $pg_home=postgres_install -pg_newhome:$($md5List.new_home) -pg_source_pack:$($md5List.file)

    stop_postgres -svc_remove
    $pg_service_name=postgres_service_install -pg_home:"$pg_home"
    postgres_initdb -pg_home:"$pg_home" -pg_old_home:"$pg_old_home"
    start_postgres -svc_match:$pg_service_name
    postgres_restore_all -pg_dumpfile:"$pg_dumpfile"
    start_postgres_deps

    LogWrite "PostgreSQL install/upgrade complete" -logwarn -logout
}

