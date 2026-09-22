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

Get-Module | Remove-Module

Import-module $module_path\Logging
Import-module $module_path\oracle_tools


write-host -f yellow "                                                     " -BackgroundColor Red
write-host -f yellow "  Database prepatch Tidy up                          " -BackgroundColor Red

# Use/Create the generated audit and select a database to process
LogWrite "Running $($MyInvocation.MyCommand.Name) Software Base directory : $basedir"
LogWrite "Parameters : $args"

# Remove old Oracle service
$discard = remove_OracleRemExecServiceV2 # Remove old Oracle service
