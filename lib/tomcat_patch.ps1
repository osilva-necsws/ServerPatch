# ChildView upgrade script - User modification strictly prohibited Copyright CACI Ltd

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
$global:resource= Resolve-Path -Path "$basedir\resource"
$global:package= Resolve-Path -Path "$basedir\package"
$global:log_path= Resolve-Path -Path "$basedir\logs"

# Get version details and settings
. $module_path\About.ps1


Get-Module | Remove-Module

Import-module $module_path\Logging
Import-module $module_path\Folder-Ident
Import-module $module_path\tomcat_tools
Import-module $module_path\tomcat_server_xml
Import-module $module_path\caci_utils

$padLeft = 'test'.PadLeft(25)

$banner_width=55

write-host -f yellow -BackgroundColor Red "".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor Red "  ChildView WebTier Patch $cv_ver : $cv_cpu".PadRight($banner_width," ") 
write-host -f yellow -BackgroundColor Red "  ===========================".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor Red "  It is critical a server backup has been performed".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor Red "  prior to running this upgrade.".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor Red "  Ensure all users are out of the system.".PadRight($banner_width," ")
write-host -f yellow -BackgroundColor Red "  ===========================".PadRight($banner_width," ")
write-host -f red  -BackgroundColor Yellow "  Please Note:".PadRight($banner_width," ")
write-host -f red  -BackgroundColor Yellow "  Webtier's can be shared between Live and Test".PadRight($banner_width," ")
write-host -f red  -BackgroundColor Yellow "  systems, so updating Test COULD take Live out".PadRight($banner_width," ") 
write-host -f red  -BackgroundColor Yellow "  of service! Please review supporting documentation".PadRight($banner_width," ") 


do {
    $confirmation = Read-Host "Please type CONFIRMED to proceed (ctrl/c to exit):"
    } while ($confirmation -ne 'CONFIRMED')


# Perform an MD5 check on any packages required
# Get-FileHash -Algorithm MD5 .\apache-tomcat-9.0.63.zip 
# Update below file and md5 details, and tomcat pack constant in tomcat_tools.psm1
$md5list = Import-Clixml -Path "$($package.path)\pack_tomcat.xml"

#$md5List = @()
#$md5List+=New-Object PsObject -property @{ name = "WebTier pack"; file = "apache-tomcat-9.0.90.zip"; md5 = "7702F8ADEA347130504CF1BDEF3CBF5D"}
#$md5list | Export-Clixml -Path C:\gitroot\deploymentdev\package\pack_tomcat.xml
$tomcat_pack="$basedir\package\$($md5list.file)"

md5_file_check $md5List $package.path

$tc_doms = @()

#$tc_doms.gettype()

$tc_doms = webtier_details $tc_doms

foreach ($webtier in $tc_doms) {
    if ($webtier.home) {tomcat_app_replacement $webtier.home}
}

#$tc_doms.gettype()

update_tomcat $tc_doms

#process_domains $tc_doms






