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
$global:package= Resolve-Path -Path "$basedir\package"
$global:log_path= Resolve-Path -Path "$basedir\logs"

Get-Module | Remove-Module

Import-module $module_path\Logging
Import-module $module_path\caci_utils

write-host -f yellow "                                                     " -BackgroundColor Red
write-host -f yellow "  ChildView Utilities - Metabase Upgrade             " -BackgroundColor Red
write-host -f yellow "  ===================================                " -BackgroundColor Red
write-host -f yellow "  Please ensure a server backup has been performed   " -BackgroundColor Red
write-host -f yellow "  or a rollback solution is available prior to       " -BackgroundColor Red
write-host -f yellow "  running this script.                               " -BackgroundColor Red
write-host -f yellow "                                                     " -BackgroundColor Red

do {
    $confirmation = Read-Host "Please type CONFIRMED to proceed (ctrl/c to exit):"
    } while ($confirmation -ne 'CONFIRMED')


# Perform an MD5 check on any packages required
# Get-FileHash .\jdk1.8.0_332.zip -Algorithm MD5
# Update below file and md5 details, and java_jdk_pack constant in caci_utils.psm1
# Load MD5 list
$md5List_metabase = Import-Clixml -Path "$package\pack_metabase.xml"

#$md5List = @()
#$md5List+=New-Object PsObject -property @{ name = "JDK pack"; file = "jdk1.8.0_412.zip"; md5 = "810C46A1EE54298C3EE3580A4B7A1110"; version="1.8.0u412"}
#$md5list | Export-Clixml -Path C:\gitroot\deploymentdev\package\pack_jdk21.xml


md5_file_check $md5List_metabase $package

# Log sciript details
LogWrite "Running $($MyInvocation.MyCommand.Name) Software Base directory : $basedir"
LogWrite "Parameters : $args"

Upgrade_Metabase -software_pack:$md5List_metabase

Logwrite "Java upgrade completed - Verify ChildView status" -logout

