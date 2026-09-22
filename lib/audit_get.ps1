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
Import-module $module_path\Component-Ident
Import-module $module_path\Service-Ident
Import-module $module_path\Folder-Ident

LogWrite "Server Audit Generation" -logout
LogWrite "=======================" -logout
LogWrite "Log path : $log_path" -logout
LogWrite "_______________________" -logout
LogWrite "Modules location - $module_path"
LogWrite "Resource location - $resource"
LogWrite "Modules loaded - Starting"

[xml]$component_list = compident_read
[xml]$complete_list = ( Select-Xml -Path "$resource/installation.xml" -XPath / ).Node

$complete_list = srvident_process $component_list $complete_list


#$comps_list = (Select-XML -Xml $component_list -Xpath "//components/component/@name").node.value
#Logwrite "Component list : $comps_list"

foldident_process $component_list $complete_list

$StringWriter = New-Object System.IO.StringWriter
$XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter
$xmlWriter.Formatting = "indented"
$xmlWriter.Indentation = 4
$complete_list.WriteContentTo($XmlWriter)
$XmlWriter.Flush()
$StringWriter.Flush()
#Write-host -f yellow $XmlWriter.ToString()
# Remove any previous file

remove-item $basedir\Platform_config.xml -ErrorAction SilentlyContinue | out-null


$comps_identified = (Select-XML -Xml $complete_list -Xpath "//components/component/@name").node

if ($comps_identified) {$comps_identified = $comps_identified.value.ToString()
    Logwrite "Components Identified : $comps_identified"

    $complete_list.Save("$basedir\Platform_config.xml")
    Logwrite "Server audit complete - found $($comps_identified.count) component(s)" -logout
} else {
    Logwrite "Server audit complete" -logout
    Logwrite "NO components found on this machine" -logfail -logout
}


Remove-module Component-Ident
Remove-module Service-Ident
Remove-module Folder-Ident

Pop-Location
