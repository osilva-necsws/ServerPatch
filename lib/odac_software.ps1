# Oracle ODAC install/upgrade script - User modification strictly prohibited Copyright CACI Ltd

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
Import-module $module_path\caci_utils

write-host -f yellow "                                                        " -BackgroundColor Red
write-host -f yellow "  Database client tools for Installer                   " -BackgroundColor Red
write-host -f yellow "  ===================================                   " -BackgroundColor Red
write-host -f yellow "  This tool provides DB support for the CACI Installer  " -BackgroundColor Red
write-host -f yellow "  Can be re-run to re-install without issue             " -BackgroundColor Red
$md5List = @()
$md5List+=New-Object PsObject -property @{ name = "ODAC pack"; file = "Oracle-Client-for-Microsoft-Tools-32-bit.exe"; md5 = "83DE72B59BF65A4C24B97C258AF168B2"; version = "19.0.0"; space=251039744}

md5_file_check $md5List $package.path

$installation_root=find_installation_roots
$install_loc="$($installation_root.DeviceID[0])\CACI\Updates\Installer\ODAC"

if (-not (test-path $install_loc)){new-item -Path $install_loc -ItemType Directory} # If folder doesnt exist, create it
LogWrite "Installing DB Client tools for installer" -loginfo -logout
$install_cmd="$package\Oracle-Client-for-Microsoft-Tools-32-bit.exe /v`"INSTALLDIR=\`"D:\CACI\Updates\Installer\ODAC`" /norestart`" /qnx"
$run_cmd = $install_cmd
LogWrite "Command: $run_cmd" -loginfo
$discard = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $run_cmd
LogWrite "Installation Complete" -logwarn -logout