# Add in unzip function
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}


function webtier_check_platform
{
  $config_xml="$basedir\Platform_config.xml"
  # Check for Audit XML file
  If (!(Test-Path $config_xml)) {
      LogWrite "No Audit file - Running Audit" -logout -logwarn
      & "$module_path\audit_get.ps1"
      LogWrite "Audit done" -logout
      If (!(Test-Path $config_xml)) {
          LogWrite -errid "abend" -logout
          exit
      }
   }

LogWrite "Audit file available" -logout

}

function webtier_details
{
  Param (
    $tc_doms
  )
  $config_xml="$basedir\Platform_config.xml"
  # Check for Audit XML file - Always re-generate audit. CPU63 onwards.
  #If (!(Test-Path $config_xml)) {
  #    LogWrite "No Audit file - Running Audit" -logout -logwarn
      & "$module_path\audit_get.ps1"
      LogWrite "Audit done" -logout
      If (!(Test-Path $config_xml)) {
          LogWrite -errid "abend" -logout
          exit
      }
   #}

  [xml]$platform

  webtier_check_platform

  LogWrite "Loading Audit file" -logout
  $platform = ( Select-Xml -Path $config_xml -XPath /).Node

  $webtiers=( Select-Xml -xml $platform -XPath "//components/component[@type='web service']").Node

  if (($webtiers.HasChildNodes)) {
      LogWrite "WebTier elements located on this server" -logout -loginfo
  } else {
      LogWrite "No webtiers discovered on this host" -logout -logwarn
      LogWrite "Verify this host contains a ChildView Webtier" -logout -logwarn
      exit
  }
    
    $tc_doms.Clear()

    LogWrite "Domains on this server" -logout -loginfo
    foreach ($domain in $webtiers) {
        LogWrite "Domain : $($domain.name)"  -logout -loginfo
        foreach ($web_folder in $domain.folders.folder) {
            logwrite "Web Folder : $($web_folder.type) : $($web_folder.'#text')" -loginfo
            if ($web_folder.type -eq "service home") {
                [string]$dom_home=($web_folder.'#text' -split "\\bin\\tomcat")[0]
                $dom_home="$($dom_home)\$($domain.name)"
            }
            if ($web_folder.type -eq "CATALINA_HOME") {$dom_home=$web_folder.'#text'}
        }

        [string]$dom_name=$domain.name
        [string]$dom_home=$dom_home
        [string]$dom_base=($dom_home -split "\\$($domain.name)")[0]

        logwrite "Domain [Name]$dom_name [home]$dom_home [base]$dom_base"

        $tc_doms+=(@{"Dom"="$dom_name" ;"Home"="$dom_home" ; "Base" = "$dom_base"})
     #   $tc_doms+=(@{"Dom"="checkit" ;"Home"="$dom_home" ; "Base" = "$dom_base"})
     #   $tc_doms+=(@{"Dom"="cv_main2" ;"Home"="$dom_home" ; "Base" = "$dom_base"})
     #   $tc_doms+=New-Object PsObject -property @{"Dom"="$dom_name" ;"Home"="$dom_home" ; "Base" = "$dom_base"}    

}


return $tc_doms

#  return $ht
}

Export-ModuleMember -Function webtier_details


function update_tomcat
{
 Param (
	$tc_doms
  )

# server.xml processing variables no longer needed (security hardening pre-applied)
# [hashtable]$server_xml_detail = @{}
# [xml]$server_xml

#write-host "Domain count $($tc_doms.count)"
$tc_doms[0]=$null
$tc_doms=$tc_doms.Where({ $_ -ne $null -and $_ -ne ""})
#write-host "Domain count filtered $($tc_doms.count)"

#if ($tc_doms.gettype().Name -eq "object[]")
#{
#    [string]$tomcat_home=$tc_doms.home[1]
if ($tc_doms.count -eq 1) {
    [string]$tomcat_base=$tc_doms.base
} else {
    [string]$tomcat_base=$tc_doms.base[1]
}
#} else {
#    [string]$tomcat_home=$tc_doms.home
#    [string]$tomcat_base=$tc_doms.base
#}



# Stop all services before updating
LogWrite "Stopping Tomcat services" -loginfo -logout
LogWrite "Tomcat Base : $tomcat_base" -loginfo

foreach ($proc_domain in $tc_doms) {
	LogWrite "Stopping service for Domain : $($proc_domain.Dom)" -loginfo
    $serviceName = $proc_domain.Dom
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running') {
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        LogWrite "Stopped service: $serviceName" -loginfo
    }
	}

# Update software

    tc_update_software $tomcat_base


# Patching configurations
LogWrite "Patching new services" -loginfo -logout

foreach ($domain in $tc_doms) {
	LogWrite "Patching Domain : $($domain.dom)" -loginfo
	LogWrite "Domain home : $($domain.Home)" -loginfo
	LogWrite "Domain Base : $($domain.Base)" -loginfo

    # server.xml security hardening has been pre-applied on all servers - skipping
    # $server_xml_detail = webtier_serverxml_init $server_xml_detail $domain.Home
    # LogWrite "Server XML file : $($server_xml_detail.filename)" -loginfo
    # $server_xml = webtier_serverxml_load $server_xml_detail 
    # remove_ajp_listener $server_xml
    # set_TLS $server_xml
    # set_err_resp $server_xml 
    
    if (test-path "$($domain.home)\webapps\ROOT\index.jsp") {
        remove-item "$($domain.home)\webapps\ROOT\index.jsp" -ErrorAction SilentlyContinue
    } else {
        LogWrite "No index.jsp to remove " -loginfo
    }
    # Remove docs folder
    $rem_folder="$($domain.home)\webapps\docs"
    if (test-path $rem_folder) {
        remove-item -recurse -force $rem_folder -ErrorAction SilentlyContinue
    } else {
        LogWrite "No docs deployment to remove - $rem_folder" -loginfo
    }
    # Remove host-manager folder
    $rem_folder="$($domain.home)\webapps\host-manager"
    if (test-path $rem_folder) {
        remove-item -recurse -force $rem_folder -ErrorAction SilentlyContinue
    } else {
        LogWrite "No host-manager deployment to remove - $rem_folder" -loginfo
    }

    # Remove manager folder
    $rem_folder="$($domain.home)\webapps\manager"
    if (test-path $rem_folder) {
        remove-item -recurse -force $rem_folder -ErrorAction SilentlyContinue
    } else {
        LogWrite "No manager deployment to remove - $rem_folder" -loginfo
    }

    # server.xml backup and save skipped (security hardening already applied)
    # $discard = webtier_serverxml_backup_and_replace $server_xml_detail $server_xml
} # foreach domain


# Restart services
LogWrite "Restarting Tomcat services" -loginfo -logout


foreach ($domain in $tc_doms) {
	LogWrite "Starting service for Domain : $($domain.Dom)" -loginfo
    $serviceName = $domain.Dom
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        Start-Service -Name $serviceName -ErrorAction SilentlyContinue
        LogWrite "Started service: $serviceName" -loginfo
    } else {
        LogWrite "WARNING: Service not found: $serviceName" -logwarn
    }
	}

LogWrite "WebTier update completed" -logout


}

Export-ModuleMember -Function update_tomcat

function tc_remove_service
{
  Param (
	$tc_domain,
    $java_loc
  )
    LogWrite "Removing service $($tc_domain.Dom)" -loginfo
    If (Get-Service $tc_domain.Dom -ErrorAction SilentlyContinue) {

        stop-service -name $tc_domain.Dom

        $env:CATALINA_HOME=$tc_domain.Home
        $env:CATALINA_BASE=$tc_domain.Base

        $env:JAVA_HOME=$java_loc
        $env:PATH="$($tc_domain.Base)\bin;$($java_loc)\bin;" + $env:PATH



        $tomcat_cmd= "service.bat uninstall $($tc_domain.Dom)"
        LogWrite "Remove Tomcat Service Cmd: $($tomcat_cmd)" -loginfo
        $tc_out = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $tomcat_cmd
    } else {
       LogWrite "Service already removed: $($tc_domain.Dom)" -loginfo
    }
}

function tc_create_service
{
  Param (
	$tc_domain,
    $java_loc
  )

    # Get defaults for memory and description
    $tomcat_defaults=tc_defaults
    $tomdom_def=$tomcat_defaults.where{$_.dom -eq "$($tc_domain.Dom)"}

    $env:CATALINA_HOME=$tc_domain.Home
    $env:CATALINA_BASE=$tc_domain.Base

    $env:JAVA_HOME=$java_loc
    $env:PATH="$($tc_domain.Base)\bin;$($java_loc)\bin;" + $env:PATH

    $tom_cmd= "service.bat install $($tc_domain.Dom)"
    LogWrite "Tomcat: Installing domain service for $($tc_domain.Dom)" -loginfo
    LogWrite "TC Service install Cmd: $($tom_cmd)" -loginfo
    $tc_out = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $tom_cmd
    LogWrite "Tomcat: Updating domain properties for $($tc_domain.Dom)" -loginfo
    $tom_cmd ="tomcat9.exe //US//$($tomdom_def.dom) $($tomdom_def.mem) --Description=`"$($tomdom_def.desc)`""
    LogWrite "TC Service update Cmd: $($tom_cmd)" -loginfo
    $tc_out = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $tom_cmd
    LogWrite "Setting domain service to auto and starting : $($tc_domain.Dom)" -loginfo
    $tc_service = Get-Service $tomdom_def.dom

    If (Get-Service $tomdom_def.dom -ErrorAction SilentlyContinue) {
        set-service -name $tomdom_def.dom -startuptype Automatic -Displayname "ChildView_$($tomdom_def.dom)" -Description "$($tomdom_def.desc)_$cv_cpu"
        start-service -name $tomdom_def.dom
    } else {
        LogWrite "Service $($tomdom_def.dom) not found" -logwarn -logout
        LogWrite -errid "abend" -logout
        exit
    }
}


function tc_update_software
{
  Param (
    [Parameter(Mandatory)]
    $tomcat_home
  )
  $tomcat_bin="$tomcat_home\bin"
  $tomcat_lib="$tomcat_home\lib"
# Check for bin and lib folders before removing bin_old and lib_old
LogWrite "Tomcat Bin : $tomcat_bin" -loginfo
LogWrite "Tomcat Lib : $tomcat_lib" -loginfo
if ((Test-Path -Path $tomcat_bin) -and (Test-Path -Path $tomcat_lib)) {

# Remove previous bin_old and lib_old folders
    $discard = Remove-Item -Path "$tomcat_home\bin_old" -Force -Recurse -ErrorAction SilentlyContinue
    $discard = Remove-Item -Path "$tomcat_home\lib_old" -Force -Recurse -ErrorAction SilentlyContinue

# Rename current bin -> bin_old and lib to lib_old

    $discard = Rename-Item "$tomcat_home\bin" "$tomcat_home\bin_old" -Force -ErrorAction SilentlyContinue  
    $discard = Rename-Item "$tomcat_home\lib" "$tomcat_home\lib_old" -Force -ErrorAction SilentlyContinue  

# Remove version files from install (Files are included in Zip)


    $discard = Remove-Item -Path "$tomcat_home\BUILDING.txt" -Force -Recurse -ErrorAction SilentlyContinue
    $discard = Remove-Item -Path "$tomcat_home\CONTRIBUTING.md" -Force -Recurse -ErrorAction SilentlyContinue
    $discard = Remove-Item -Path "$tomcat_home\LICENSE" -Force -Recurse -ErrorAction SilentlyContinue
    $discard = Remove-Item -Path "$tomcat_home\NOTICE" -Force -Recurse -ErrorAction SilentlyContinue
    $discard = Remove-Item -Path "$tomcat_home\README.md" -Force -Recurse -ErrorAction SilentlyContinue
    $discard = Remove-Item -Path "$tomcat_home\RELEASE-NOTES" -Force -Recurse -ErrorAction SilentlyContinue
    $discard = Remove-Item -Path "$tomcat_home\RUNNING.txt" -Force -Recurse -ErrorAction SilentlyContinue


# Upzip new bin and lib folders in place

     LogWrite "Unpacking Updated WebTier software" -loginfo -logout
     # Unzip installation pack to location
     LogWrite "Attempting unpack : $tomcat_pack -> $tomcat_home" -loginfo
     unzip $tomcat_pack $tomcat_home

    if ((Test-Path -Path $tomcat_bin) -and (Test-Path -Path $tomcat_lib)) {
     LogWrite "Unpacking Updated WebTier software complete $tomcat_pack -> $tomcat_home" -loginfo
     LogWrite "WebTier software deployed" -logout
    } else {
    LogWrite "Tomcat upgrade has failed - Unpacking new software issue" -logwarn -logout
    LogWrite -errid "abend" -logout;
    exit

    }

} else {
    LogWrite "Tomcat upgrade has failed" -logwarn -logout
    LogWrite -errid "abend" -logout;
    exit
}


}

function tomcat_app_replacement
{
    Param (
        [Parameter(Mandatory)]
        $tomcat_home,
        $domain_name,
        $tomcat_app="FileHandler",
        $app_file="FileHandler.war",
        $app_source="$package\$app_file",
        $tomcat_webapp="webapps"
    )

    # Only deploy FileHandler to cv_maint domain, do not delete, only add if missing, never fail
    try {
        if ($domain_name -eq "cv_maint") {
            $tomcat_deployed = "$tomcat_home\$tomcat_webapp"
            $app_deployed = "$tomcat_deployed\$app_file"
            if (-not (Test-Path -Path $app_deployed)) {
                if (Test-Path -Path $app_source) {
                    LogWrite "FileHandler.war not found in $tomcat_deployed. Deploying new FileHandler.war..." -logout
                    Copy-Item -Path $app_source -Destination $tomcat_deployed -ErrorAction SilentlyContinue
                    LogWrite "FileHandler.war deployed to $tomcat_deployed" -logout
                } else {
                    LogWrite "FileHandler.war source not found at $app_source. Deployment skipped." -logout -logwarn
                }
            } else {
                LogWrite "FileHandler.war already exists in $tomcat_deployed. No action taken." -logout
            }
        } else {
            LogWrite "Skipping FileHandler deployment for domain $domain_name" -logout
        }
    } catch {
        LogWrite "Non-fatal error during FileHandler deployment: $_" -logout -logwarn
        # Never throw, always continue
    }
}
Export-ModuleMember -Function tomcat_app_replacement

function tc_defaults
{  

# Tomcat Domains

$tomcat_domains=@()
$tomcat_domains+=New-Object PsObject -property @{ dom = "cv_main"; service = "ChildView_Main"; base = "cv_main"; installed = $false ; serviced = $false; mem = "-JvmMx=512 --JvmMs=512"; desc = "CACI ChildView - Main Access services"; installed_base = "None" }
$tomcat_domains+=New-Object PsObject -property @{ dom = "cv_support"; service = "ChildView_Support"; base = "cv_support"; installed = $false; serviced = $false; mem = "-JvmMx=2048 --JvmMs=2048"; desc = "CACI ChildView - Support services"; installed_base = "None"}
$tomcat_domains+=New-Object PsObject -property @{ dom = "cv_maint"; service = "ChildView_maint"; base = "cv_maint"; installed = $false; serviced = $false; mem = "-JvmMx=256 --JvmMs=256"; desc = "CACI ChildView - Maintainence services"; installed_base = "None" }
$tomcat_domains+=New-Object PsObject -property @{ dom = "cv_yjb"; service = "ChildView_YJB"; base = "cv_yjb"; installed = $false; serviced = $false; mem = "-JvmMx=256 --JvmMs=256"; desc = "CACI ChildView - YJB services"; installed_base = "None" }

return $tomcat_domains
}







