

$database_id=$args[0]

$scriptdir = split-path $PSScriptRoot -leaf

if ($scriptdir="lib")
{
   $basedir = Resolve-Path -Path "$PSScriptRoot\.."
} else {
    $basedir = Resolve-Path -Path "$PSScriptRoot"
}

# write-host -f yellow "Running $($MyInvocation.MyCommand.Name) Software Base directory : $basedir"

Push-Location $basedir


$global:module_path= Resolve-Path -Path "$basedir\lib"
$global:resource= Resolve-Path -Path "$basedir\resource"
$global:log_path= Resolve-Path -Path "$basedir\logs"


Import-module $module_path\Logging

LogWrite "Running $($MyInvocation.MyCommand.Name) Software Base directory : $basedir"
LogWrite "Parameters : $args"

LogWrite "ChildView Database Backup" -logout
LogWrite "=========================" -logout
LogWrite "Log path : $log_path" -logout
LogWrite "_________________________" -logout
LogWrite "Modules location - $module_path"
LogWrite "Resource location - $resource"
LogWrite "Modules loaded - Starting"


$config_xml="$basedir\Platform_config.xml"

# Check for Audit XML file - Always run audit cpu_63 and later
#If (!(Test-Path $config_xml)) {
#    LogWrite "No Audit file - Running Audit" -logout -logwarn
    & "$module_path\audit_get.ps1"
    LogWrite "Audit done" -logout
    If (!(Test-Path $config_xml)) {
        LogWrite -errid "abend" -logout
        exit
    }
#}


LogWrite "Loading Audit file" -logout
[xml]$platform_config = ( Select-Xml -Path $config_xml -XPath /).Node

$oracle_dbs = ( Select-Xml -xml $platform_config -XPath "//components/component[@type='db service']").Node
#[xml]$oracle_dbs = ( Select-Xml -Path $config_xml -XPath /).Node

if ($oracle_dbs.count -gt 0) {
    if ($database_id) {
        LogWrite "Database name $database_id"
    } else {
        LogWrite "No database name supplied" -logwarn
        $database_id=db_choice
        $selected_db=( Select-Xml -xml $oracle_dbs -XPath "//components/component[@name='$($database_id)']").Node

    }

} else {
    LogWrite "No databases discovered on this host" -logout -logwarn
}

return $selected_db

Remove-module Logging

Pop-Location
