param (
   [string]$configFile="D:\CACI\WebTier\Config\ApacheAAP_cfg.xml",
   [switch]$createConfigfileOnly = $false
)
#Requires -Version 3.0
#Requires -RunAsAdministrator

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

Import-module $module_path\Logging

$installSet = @{}                                                                               
$installSet.add("cfgLoc",$configFile)                                                       # cfgloc : The configuration file name (supplied as a parameter with a default value D:\CACI\WebTier\Config\ApacheAAP_cfg.xml)
$installSet.add("vccPkg","vc_redist.x64.exe")                                               # vccPkg : The vcc redistributable pack in the packages folder
$installSet.add("vccMin","Microsoft Visual C++ 2022 X64 Minimum Runtime - 14.42.34433")     # vccMin : The registered name for the vcc version
$installSet.add("vccAdd","Microsoft Visual C++ 2022 X64 Additional Runtime - 14.42.34433")  # vccAdd : The registered name for the vvc version (additional)
$installSet.add("apaInstall","D:\CACI\WebTier\ApacheAAP")                                   # apaInstall : Installation folder for Apache
$installSet.add("apaBase","D:\CACI\WebTier\ApacheAAP\Apache24")                             # apaBase : Apache base location
$installSet.add("apaPkg","httpd-2.4.62-240904-win64-VS17.zip")                              # apaPkg : The apache source package
$installSet.add("apaCfg","AAP_httpd.conf")                                                  # apaCfg : Source template file (from resources) 
$installSet.add("apaCfgProxy","AAP_httpd_proxy.conf")                                       # apaCfgProoxy : Source template file (from resources)
$installSet.add("apaSvc","Apache24 for Azure Application Proxy")                            # apaSvc : The Apache service name
$installSet.add("prxUrlTest","cv-proxy-test.caci.co.uk")                                    # prxUrlTest : Azure App Proxy URL for Test system (ports 8*)
$installSet.add("prxUrlProd","cv-proxy-prod.caci.co.uk")                                    # prxUrl : Azure App Proxy URL for Prod system (ports 9*)
$installSet.add("cvUrl","lon-cygweb-01.cyp.caci.co.uk")                                     # cvUrl : ChildView host URL



# Read a config file if it exists, attempt to write the defaults above out to one if it doesnt.

if (test-path $configFile){
   $installSet = Import-Clixml -Path $configFile
} else {
   $installSet | Export-Clixml -Path $configFile
}

if ($createConfigfileOnly){
   logwrite "Config file location $configFile" -logout -logwarn
   logwrite "Exiting. Please update the config file above, and rerun to use those settings." -logout -logwarn
   exit
}

# Add 7Zip command if executable exists - used for Jar pom.xml file extraction.
$7zExe = "$module_path\7za.exe"
if (test-path $7zExe){
    set-alias 7zextract $7zExe
    $7zAvail=$true
} else {
    $7zAvail=$false
}

# Check VCC redist is installed, install it if missing.
$vcc_installed = Get-CimInstance -Class Win32_Product | Where-Object { $_.Name -eq $($installSet.vccMin) -or $_.Name -eq $($installSet.vccAdd)}

if ($vcc_installed.count -eq 2) {logwrite "VCC is already installed" -logout -logwarn; $checkvcc=$false} else {
   $vccProcess = start-process -FilePath "$package/$($installSet.vccPkg)" -ArgumentList "/install /quiet /norestart" -Verb RunAs -passthru
   $checkvcc=$true
}

# Check and unziop Apache to installation directory
if (test-path $installSet.apaBase) {logwrite "Apache is already deployed" -logout -logwarn} else {
   logwrite "Extracting Apache source $package/$($installSet.apaPkg) to $($installSet.apaInstall)" -logout
   $extractApa= 7zextract x -y "$package/$($installSet.apaPkg)" -o"$($installSet.apaInstall)" Apache24
   logwrite ($extractApa | out-string)
   if ($extractApa.contains("Everything is Ok")) {logwrite "Extraction Complete" -logout -logwarn} else {logwrite "Extraction failed - review logfile" -logout -logfail}
}

# Check VCC install has completed
while ($checkvcc -and $vccProcess.HasExited) {logwrite "Waiting for VCC to complete installation" -logout; start-sleep -seconds 10}

# Setup httpd configuration
$apacheCfg = get-content -Path "$resource/$($installSet.apaCfg)"
# Update settings
$srvroot = ($installSet.apabase).replace("\","/")
$apacheCfg = $apacheCfg.replace('[srvRoot]',$srvroot)
$apacheCfg = $apacheCfg.replace('[lsnPort]','443')
$apacheCfg | out-file "$($installSet.apaBase)/conf/httpd.conf" -Encoding ASCII

# Setup Proxy configuration
$apacheCfgProxy = get-content -Path "$resource/$($installSet.apaCfgProxy)"
# Update settings
$srvroot = ($installSet.apabase).replace("\","/")
$apacheCfgProxy = $apacheCfgProxy.replace('[proxyUrlTest]',"$($installSet.prxUrlTest)")
$apacheCfgProxy = $apacheCfgProxy.replace('[proxyUrlProd]',"$($installSet.prxUrlProd)")
$apacheCfgProxy = $apacheCfgProxy.replace('[cvUrl]',"$($installSet.cvUrl)")
$apacheCfgProxy | out-file "$($installSet.apaBase)/conf/httpd_aap.conf" -Encoding ASCII

#Install Apache as a service
$check_svc = get-service -name "$($installSet.apaSvc)" -ErrorAction SilentlyContinue
if ($check_svc){
   logwrite "Service already exists [$($installSet.apaSvc)] - Removing" -logout -logwarn
   Stop-Service "$($check_svc.name)" 
   $service = Get-CimInstance -ClassName Win32_Service -Filter "Name=`'$($check_svc.name)`'"
   $service | Remove-CimInstance
}
$apacheCmd = "$($installSet.apaBase)\bin\httpd.exe -k install -n `"$($installSet.apaSvc)`" 2>&1"
$apacheSrv = invoke-expression -command $apacheCmd 
#$apacheSrv =  invoke-expression("$($installSet.apaBase)\bin\httpd.exe -k install -n `"$($installSet.apaSvc)`"")
logwrite ($apacheSrv | out-string)
if ($apacheSrv.contains('Errors reported here must be corrected before the service can be started.')) {logwrite "Apache - Issue with service/configuration - Review Logfile" -logout -logfail}
