# Oracle ODAC install/upgrade script - User modification strictly prohibited Copyright CACI Ltd

# Add in unzip function
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

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
$md5List+=New-Object PsObject -property @{ name = "ODAC pack"; file = "ODAC19.20Xcopy_x86.zip"; md5 = "66129522E9B77CEA5A51FCD0EC705791"; version = "19.0.0"; space=251039744}

md5_file_check $md5List $package.path

$installation_root=find_installation_roots

if ($($installation_root.DeviceID[0]) -match ':') {
    LogWrite "Device returned with :" -loginfo
    $install_loc="$($installation_root.DeviceID[0])\CACI\WebTier\Installer\ODAC19c"
    $stage_loc="$($installation_root.DeviceID[0])\CACI\WebTier\Installer\ODAC19c_stage"
} else { 
    LogWrite "Device missing :" -loginfo
    $install_loc="$($installation_root.DeviceID[0]):\CACI\WebTier\Installer\ODAC19c"
    $stage_loc="$($installation_root.DeviceID[0]):\CACI\WebTier\Installer\ODAC19c_stage"
}



$odac_pack = "$basedir\package\$($md5list.file)"
if (-not (test-path $install_loc)){new-item -Path $install_loc -ItemType Directory | out-null } # If folder doesnt exist, create it
if (-not (test-path $stage_loc)){
    new-item -Path $stage_loc -ItemType Directory
} # If folder doesnt exist, create it
else {
    remove-item -recurse -force $stage_loc -ErrorAction SilentlyContinue 
    new-item -Path $stage_loc -ItemType Directory | out-null
}
LogWrite "Extracting software to Staging" -loginfo -logout

LogWrite "Extracting from $odac_pack -> $stage_loc" -loginfo
unzip $odac_pack $stage_loc

LogWrite "Installing DB Client tools for installer" -loginfo -logout
#$run_cmd = "install.bat odp.net4 $install_loc CACI_ODAC true true $install_loc"
$run_cmd = "install.bat all $install_loc CACI_ODAC true true $install_loc"

# $install_cmd="$package\Oracle-Client-for-Microsoft-Tools-32-bit.exe /v`"INSTALLDIR=\`"D:\CACI\Updates\Installer\ODAC`" /norestart`" /qnx"
LogWrite "Command: $run_cmd" -loginfo
Push-Location $stage_loc
$discard = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $run_cmd -ErrorVariable errortext 2>$null

LogWrite "ODAC Install output : $discard" -loginfo
LogWrite "ODAC Install error : $errortext" -loginfo
Pop-Location
LogWrite "Installation Complete" -logwarn -logout


# Check for registered assembly's with powershell:
# Get-Item -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319\AssemblyFoldersEx\Oracle*