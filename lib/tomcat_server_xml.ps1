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
Import-module $module_path\tomcat_tools
Import-module $module_path\tomcat_server_xml


[hashtable]$server_xml_detail = @{}
[xml]$server_xml

$server_xml_detail = webtier_serverxml_init $server_xml_detail "C:\CACI\WebTier\tomcat\cv_main"

$server_xml = webtier_serverxml_load $server_xml_detail 
remove_ajp_listener $server_xml
set_TLS $server_xml
set_err_resp $server_xml 
$discard = webtier_serverxml_backup_and_replace $server_xml_detail $server_xml 