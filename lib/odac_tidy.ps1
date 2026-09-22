# Oracle ODAC Tidyscript - User modification strictly prohibited Copyright CACI Ltd

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

write-host -f yellow "                                                                 " -BackgroundColor Red
write-host -f yellow "  Database client tools Tidy                                     " -BackgroundColor Red
write-host -f yellow "  ===================================                            " -BackgroundColor Red
write-host -f yellow "  This tool tidies up older ODAC's from the server               " -BackgroundColor Red
write-host -f yellow "  Can take some time to execute depending on server performance. " -BackgroundColor Red

LogWrite "Finding Registered ODAC:" -loginfo
$installed_odac = Get-ItemProperty -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\*\AssemblyFoldersEx\ODP*
LogWrite "    $installed_odac" -loginfo
# $S = {[math]::Round(($this.Length / 1MB), 2)}
#$base = {(($this.'(default)' -split 'ODP.NET')[0] -split 'ASP.NET')[0] }
#$version = {(($this.'(default)' -split 'product\\')[1] -split '\\')[0] }
#$base = {(($this.'(default)'))}
# -MemberType ScriptMethod -Name "SizeInMB" -Value $S
#$installed_odac | Add-Member -NotePropertyName OdacRoot -NotePropertyValue $base
#$installed_odac | Add-Member -MemberType ScriptMethod -Name "ODAC_Base" -Value $base
#$installed_odac | Add-Member -MemberType ScriptMethod -Name "ODAC_Ver" -Value $version

$inuse_odac = (get-item $installed_odac.'(default)').parent.parent.fullname | sort-object -unique
LogWrite "In use installation: $inuse_odac" -loginfo

LogWrite "Searching machine for ODAC installations...Can take some time. (10-15 minutes)" -logwarn -logout
$drive_check = ((get-psdrive -psprovider filesystem) | where-object {$_.Name -in 'D'..'Z'}) 

#$odac_hits = get-item (get-childitem -path  $drive_check.Root -recurse -include '*\odp.net\Oracle.DataAccess.dll' -ErrorAction SilentlyContinue)  
$odac_hits = get-item (get-childitem -path  $drive_check.Root -recurse -include 'Oracle.DataAccess.dll' -ErrorAction SilentlyContinue | where-object {$_.fullname -like '*\odp.net*Oracle.DataAccess.dll'})
$odac_dir = (get-item ($odac_hits.fullname)).directory.parent.parent.fullname | sort-object -unique
foreach ($odac_loc in $odac_dir) {
    if ($odac_loc.tolower().startswith($inuse_odac.tolower())) {
        LogWrite "Keeping : $odac_loc" -loginfo
    } else {
    LogWrite "Removing : $odac_loc" -logwarn
    # Remove-Item -LiteralPath $odac_loc -Force -Recurse -ErrorAction SilentlyContinue
    }
}
LogWrite "Completed scan and removal." -logwarn -logout

# Check for registered assembly's with powershell:
# Get-Item -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.2232\AssemblyFoldersEx\Oracle*
# New-ItemProperty -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.2232\AssemblyFoldersEx\Oracle.ManagedDataAccess.EntityFramework6
# set-item -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.2232\AssemblyFoldersEx\Oracle.ManagedDataAccess.EntityFramework6 -Value "E:\CACI\DBTier\product\19.19.0\dbhome_1\ODP.NET\managed\common\EF6\"
#[microsoft.win32.registry]::SetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.2288\AssemblyFoldersEx\Oracle.ManagedDataAccess.EntityFramework6", "testkey", "E:\CACI\DBTier\product\19.12.0\dbhome_1\ODP.NET\managed\common\EF6\")
#[microsoft.win32.registry]::SetValue("HKEY_CURRENT_USER\Software\Test", "Test-DW", 0xff)