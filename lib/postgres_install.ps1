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
write-host -f yellow "  Postgres Database Installation                     " -BackgroundColor Red
write-host -f yellow "  ==============================                     " -BackgroundColor Red
write-host -f yellow "  Please be aware this tool is designed              " -BackgroundColor Red
write-host -f yellow "  For servers with no current PostgreSQL install     " -BackgroundColor Red

do {
    $confirmation = Read-Host "Please type CONFIRMED to proceed (ctrl/c to exit):"
    } while ($confirmation -ne 'CONFIRMED')

LogWrite "Running $($MyInvocation.MyCommand.Name) Software Base directory : $basedir"
LogWrite "Parameters : $args"

# Perform an MD5 check on any packages required
# Get-FileHash -Algorithm MD5 .\apache-tomcat-9.0.63.zip 
# Update below file and md5 details, and tomcat pack constant in tomcat_tools.psm1


# Perform an MD5 check on any packages required
$md5list = Import-Clixml -Path "$($package.path)\pack_postgres_home.xml"
#$md5List = @()
#$md5List+=New-Object PsObject -property @{ name = "Postgres pack"; file = "postgresql-14.11-1-windows-x64-binaries.zip"; md5 = "F0BFC1D3283F9C06A664CBF2B5D2E228"; new_home = "14.11"}
#$md5list | Export-Clixml -Path C:\gitroot\deployment-dev\package\pack_postgres_home.xml

md5_file_check $md5List $package.path

LogWrite "Postgres Database Install" -logout
LogWrite "=========================" -logout
LogWrite "Log path : $log_path" -logout
LogWrite "_________________________" -logout
LogWrite "Modules location - $module_path"
LogWrite "Resource location - $resource"
LogWrite "Modules loaded - Starting"

# Install a New PostgreSQL home. Excludes the C drive by default. To include, comment out below, and uncomment the following line.

$pg_home=postgres_install -new_install -pg_newhome:$($md5List.new_home) -pg_source_pack:$($md5List.file)
# $pg_home=postgres_install -new_install -include_c

$pg_service_name=postgres_service_install -pg_home:"$pg_home"
postgres_initdb -pg_home:"$pg_home" -pg_old_home:"$pg_home"
start_postgres -svc_match:$pg_service_name

postgres_restore_all -pg_dumpfile:"$resource\seed_new_postgres.sql"

LogWrite "PostgreSQL install complete" -logwarn -logout
