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
$global:log_path= Resolve-Path -Path "$basedir\logs"
$global:package= Resolve-Path -Path "$basedir\package"


# Get version details and settings
. $module_path\About.ps1


Get-Module | Remove-Module

Import-module $module_path\Logging
Import-module $module_path\oracle_tools
Import-module $module_path\oracle_select
Import-module $module_path\oracle_install_home
Import-module $module_path\oracle_upgrade_db
Import-module $module_path\caci_utils
Import-module $module_path\Folder-Ident



write-host -f yellow -BackgroundColor Red "".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor Red "  ChildView Database Patch $cv_ver : $cv_cpu".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor Red "  ================================".PadRight($banner_width," ") 
write-host -f yellow -BackgroundColor Red "  It is critical a server backup has been performed".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor Red "  prior to running this upgrade.".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor Red "  Ensure all users are out of the system.".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor Red "  ===========================".PadRight($banner_width," ")

# Skip confirmation if running under automation (CI environment) or if database_id is provided
$isAutomation = $env:CI -eq "true" -or ![string]::IsNullOrWhiteSpace($database_id)

if (-not $isAutomation) {
    do {
        $confirmation = Read-Host "Please type CONFIRMED to proceed (ctrl/c to exit):"
    } while ($confirmation -ne 'CONFIRMED')
} else {
    LogWrite "Running in automation mode - skipping confirmation prompt"
    if (![string]::IsNullOrWhiteSpace($database_id)) {
        LogWrite "Database ID provided via parameter: $database_id"
    }
}

# Use/Create the generated audit and select a database to process
LogWrite "Running $($MyInvocation.MyCommand.Name) Software Base directory : $basedir"
LogWrite "Parameters : $args"

# Perform an MD5 check on any packages required
# Get-FileHash -Algorithm MD5 .\apache-tomcat-9.0.63.zip 
# Update below file and md5 details, and tomcat pack constant in tomcat_tools.psm1


# Perform an MD5 check on any packages required
$md5list = Import-Clixml -Path "$($package.path)\pack_oracle_dbhome.xml"
#
#$md5List+=New-Object PsObject -property @{ name = "Database pack"; file = "WINDOWS.X64_192300_db_home.zip"; md5 = "6AA6404A88540CC3903E674D21AF9830"; version = "19.23.0"; space=10399592448; bck_tag="PRE1923PTCH"}
#$md5list | Export-Clixml -Path C:\gitroot\deployment-dev\package\pack_oracle_dbhome.xml

md5_file_check $md5List $package.path

[hashtable]$db_details = @{}

# Choose a database - skip interactive selection if database_id is provided
if (![string]::IsNullOrWhiteSpace($database_id)) {
    LogWrite "Using provided database ID: $database_id"
    $discard = choose_db -db_details $db_details -database_id $database_id
} else {
    LogWrite "Interactive database selection"
    $discard = choose_db -db_details $db_details
}

#backup database
$discard = rman_backup_std $db_details "$($md5List.bck_tag)"

# Install Database home
$discard = remove_OracleRemExecServiceV2 # Remove old Oracle service
$discard = oracle_install_new_home  -db_details:$db_details -software_pack:$md5list

# Upgrade database
$discard = oracle_upgrade_db $db_details