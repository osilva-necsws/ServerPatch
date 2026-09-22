# Run testing_

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
Import-module $module_path\oracle_select
Import-module $module_path\oracle_install_home
Import-module $module_path\oracle_upgrade_db
Import-module $module_path\oracle_upgrade_apex
Import-module $module_path\Folder-Ident

[hashtable]$db_details = @{}

# Choose a database
$discard = choose_db $db_details

$db_details.ORACLE_HOME="C:\CACI\DBTier\product\19.3.0\dbhome_1"
$db_details.Add('NEW_HOME',"C:\CACI\DBTier\product\19.9.0\dbhome_1")

check_create_spfile $db_details


