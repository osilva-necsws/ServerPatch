# Add in unzip function
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}


Function find_installation_roots
{
   Param (
     [string]$folder_match = "CACI",
     [switch]$include_c
   ) 
   LogWrite "Looking for CACI installation locations $folder_match" -loginfo
   $disks = gwmi win32_logicaldisk -Filter "DriveType='3'"
   if ($include_c) {
    $avail = $disks | ? { $_.DeviceID -notmatch "[abz]:"}
   } else {
    $avail = $disks | ? { $_.DeviceID -notmatch "[abcz]:"}
   }
   $found_locs=@()
   foreach ($drive in $avail){

       [string]$check_loc = $drive.DeviceID + "\" + $folder_match
       LogWrite "Checking on drive for $check_loc" -loginfo

         If (Test-Path $check_loc) {
            LogWrite "Found $check_loc" -loginfo
            $found_locs+=$drive
         }
   }
    return $found_locs | Sort-Object DeviceID -Unique
}

Export-ModuleMember -Function find_installation_roots


Function new_caci_dbtier
{
   Param (
     [switch]$include_C
   ) 
   $disks = gwmi win32_logicaldisk -Filter "DriveType='3'"
    if ($include_C) {
        $avail = $disks | ? { $_.DeviceID -notmatch "[abz]:"}
    } else {
        $avail = $disks | ? { $_.DeviceID -notmatch "[abcz]:"}
    }
    if (-not $avail) {
        LogWrite "Unable to find a valid install drive and cannot continue" -logout -logfail
        LogWrite "If installation on C drive required use the include_c parameter switch" -logout -logwarn
        exit
    }
    # Using first disk in the list
    $caci_drive=($avail | Select-Object -first 1)
    $caci_dbtier="$($caci_drive.DeviceID)\CACI\DBTier"
    LogWrite "Creating new CACI Root $caci_dbtier" -logout
    New-Item -Path $caci_dbtier -ItemType "directory" | out-null
    return $caci_drive
}
Export-ModuleMember -Function new_caci_dbtier

Function install_find_files
{
    Param (
      [string]$install_base,
      [string]$file_match,
      [switch]$remove_file
    )
    $found_files=Get-ChildItem -Path $install_base -Filter $file_match -Recurse -ErrorAction SilentlyContinue -Force
    foreach ($filehit in $found_files) { LogWrite "     File hit : $($filehit.FullName)"  -loginfo}
    return $found_files
}

Export-ModuleMember -Function install_find_files

function remove_files
{
    Param (
        $file_list
        )

    foreach ($delfile in $file_list) {
        LogWrite "Attempting removal : $($delfile.fullname)" -loginfo
        Remove-Item -Path $($delfile.fullname) -ErrorAction SilentlyContinue -Force
        if (test-path $($delfile.fullname)){
            LogWrite "Failed to remove $($delfile.fullname) please attempt manually" -logwarn -logout
        } else {
            LogWrite "   removed" -loginfo
        }
    }
}

Export-ModuleMember -Function remove_files

function find_Java_services
{
#    $Java_services = Get-WmiObject win32_service | ?{$_.state -eq 'Running' -and ($_.PathName -like '*CACI\WebTier\tomcat*' -or $_.PathName -like '*CACI\WebTier\portals*')}
    $Java_services = Get-CimInstance -ClassName win32_service | ?{$_.state -eq 'Running' -and ($_.PathName -like '*CACI\WebTier\tomcat*' -or $_.PathName -like '*CACI\WebTier\portals*')}
    return $Java_services
}

function Upgrade_Java_JDK
{
    Param (
        $software_pack
        )

    $java_jdk_pack="$basedir\package\$($software_pack.file)"
    $java_jdk_version="$($software_pack.version)"
    # Find installed CACI software
    LogWrite "Checking for Java installation" -loginfo

    $install_path="CACI\WebTier\Java\JDK"

    $install_roots = find_installation_roots $install_path -include_c

    if ($install_roots.count -eq 0) {
        LogWrite "No ChildView Java home found on server" -logwarn -logout
        exit
    }

    $Java_home=$install_roots.DeviceID + "\" + $install_path

    LogWrite "Java home target : $java_home" -loginfo

    LogWrite "Java JDK Update for ChildView" -logout

    # Stop Services using Java

    $Java_Services = find_java_services

    LogWrite "In use by $($java_services.count) services, Stopping services" -loginfo -logout

    foreach ($java_Service in $java_Services) {LogWrite "    $($java_service.name)" -loginfo}

    $java_services | Invoke-CimMethod -Name StopService  | Out-Null

    LogWrite "Grace period for service shutdown (2 minutes)" -loginfo -logout

    # Grace period for shutdown commands

    Start-Sleep -s 120

    # Check for Old and remove

        if (test-path "$($Java_home)_old"){
            LogWrite "Old folder exists, removing" -loginfo
            Remove-Item "$($Java_home)_old" -Recurse -ErrorAction SilentlyContinue -Force
        }

    # Rename Java/JDK to Old
    try {
            Rename-Item $Java_home "$($Java_home)_old" -ErrorAction 'Stop'
        } 
    catch
        {
            LogWrite "Java JDK Home is in use, unable to replace." -logwarn -logout
            LogWrite "Restarting Services and exiting." -logwarn -logout
            $java_services | Invoke-CimMethod -Name StartService  | Out-Null
            LogWrite "Failed to upgrade Java" -logfail -logout
        }
    # If successful (no file locks) deploy new version of Java

    LogWrite "Unpacking software distribution (avg <1 minute elapse)" -logwarn -logout
     # Unzip installation pack to location
     unzip $java_jdk_pack $Java_home

    # Restart all the Java using services
    LogWrite "Restarting $($java_services.count) Services and exiting." -logwarn -logout
    $java_services | Invoke-CimMethod -Name StartService | Out-Null

    # Tidy up
    Remove-Item "$($Java_home)_old" -Recurse -ErrorAction SilentlyContinue -Force

    return $portals_services
}

Export-ModuleMember -Function Upgrade_Java_JDK

function md5_file_check
{
    Param (
        $file_list,
        $base_folder
        )

foreach ($check_md5 in $file_list) {
    $full_path="$base_folder\$($check_md5.file)"
	    if (Test-Path -Path $full_path){
            Logwrite "Checking required package for $($check_md5.name)" -logout
    	    if ($check_md5.md5 -ne (Get-FileHash $full_path -algorithm MD5).Hash) {
                LogWrite "Checksum of file $($check_md5.name) is incorrect" -logout -logwarn
                LogWrite "Please verify the download/extraction" -logout -logwarn
                LogWrite "Possible download/extraction failure or AV scanner issue" -logout -logwarn
                LogWrite "Unable to continue patching." -logout -logwarn
                exit
            } else {
            Logwrite "file exists and checksum ok" -logout
            }
	    } else {
            LogWrite "Missing package $($check_md5.name)" -logout -logwarn
            LogWrite "Please verify the download/extraction" -logout -logwarn
            LogWrite "Possible download/extraction failure or AV scanner issue" -logout -logwarn
            LogWrite "Unable to continue patching." -logout -logwarn
            exit
        }
    }
}

Export-ModuleMember -Function md5_file_check

function odac_install
{
    Param (
        $odac_pack="$base_folder\",
        $base_folder
        )

foreach ($check_md5 in $file_list) {
    $full_path="$base_folder\$($check_md5.file)"
	    if (Test-Path -Path $full_path){
            Logwrite "Checking required package for $($check_md5.name)" -logout
    	    if ($check_md5.md5 -ne (Get-FileHash $full_path -algorithm MD5).Hash) {
                LogWrite "Checksum of file $($check_md5.name) is incorrect" -logout -logwarn
                LogWrite "Please verify the download/extraction" -logout -logwarn
                LogWrite "Possible download/extraction failure or AV scanner issue" -logout -logwarn
                LogWrite "Unable to continue patching." -logout -logwarn
                exit
            } else {
            Logwrite "file exists and checksum ok" -logout
            }
	    } else {
            LogWrite "Missing package $($check_md5.name)" -logout -logwarn
            LogWrite "Please verify the download/extraction" -logout -logwarn
            LogWrite "Possible download/extraction failure or AV scanner issue" -logout -logwarn
            LogWrite "Unable to continue patching." -logout -logwarn
            exit
        }
    }
}

Export-ModuleMember -Function odac_install

function ords_db_update
{
    Param (
        $WebTierApexEnv,
        $webConfig,
        [switch]$output_orasql,
        [string]$sqlFilename
        )

    LogWrite "Ords Update in : $webConfig" -logout
    $defaultXml = "$webconfig\$($WebTierApexEnv.OracleDB.configXML)"
    LogWrite "Setting Host/Port/Service in Ords Update in : $defaultXML" -logout

    $defaultXML_file = [xml](Get-Content -Path $DefaultXML)
    $node = $defaultXML_file.properties.entry | Where-Object {$_.key -eq 'db.hostname'}
    $node.'#text' = $WebTierApexEnv.oracleDB.HOST
    $node = $defaultXML_file.properties.entry | Where-Object {$_.key -eq 'db.port'}
    $node.'#text' = $WebTierApexEnv.oracleDB.PORT
    $node = $defaultXML_file.properties.entry | Where-Object {$_.key -eq 'db.servicename'}
    $node.'#text' = $WebTierApexEnv.oracleDB.SID

    $defaultXML_file.Save($DefaultXML)


    

    foreach ($ordsAccount in $WebTierApexEnv.oracleDB.creds) {
        if ($ordsAccount.use -eq 'ords'){
            LogWrite "Setting account $($ordsAccount.username) in $($ordsAccount.configXML)" -logout
            $defaultXml = "$webconfig\$($ordsAccount.configXML)"
            $defaultXML_file = [xml](Get-Content -Path $DefaultXML)
            $node = $defaultXML_file.properties.entry | Where-Object {$_.key -eq 'db.password'}
            $node.'#text' = $ordsAccount.password
            $defaultXML_file.Save($DefaultXML)
            if ($output_orasql) {Add-Content -Path $sqlFilename -Value "Alter user $($ordsAccount.username) identified by '$($ordsAccount.password)';"}
        }
    }
}

Export-ModuleMember -Function ords_db_update

function tomcat_pool_update
{
    Param (
        $installed_drive,
        $WebTierApexEnv,
        $platformEnv,
        [switch]$output_orasql,
        [string]$sqlFilename,
        [switch]$support_pool,
        [switch]$yjb_pool
        )

    $tomcat_base=$installed_drive + $platformEnv.defaultInstallPath + "\tomcat"
    LogWrite "Tomcat JDBC Pool Update in : $tomcat_base" -logout -logwarn
    if ($support_pool){LogWrite "  Support Pool Update" -logout}
    if ($yjb_pool){LogWrite "  YJB Pool update" -logout}

    if ($support_pool){
        $poolXml = $installed_drive + $platformEnv.cv_support_xml
        $poolXmlFile = [xml](Get-Content -Path $poolXml)

        $poolCreds=$WebTierApexEnv.oracleDB.creds | where-object use -eq "tomcatSupportPool"

        $node = $poolXmlFile.Server.GlobalNamingResources.resource | where-object name -eq $poolCreds.poolName
        $node.username = $poolCreds.username
        $node.password = $poolCreds.password
        $node.url = "jdbc:oracle:thin:@//" + $WebTierApexEnv.oracleDB.HOST + ":" + $WebTierApexEnv.oracleDB.PORT + "/" + $WebTierApexEnv.oracleDB.SID
        $poolXmlFile.Save($poolXml)
        LogWrite "Updated $poolXml with credentials for $($poolCreds.username)" -logout
        if ($output_orasql) {Add-Content -Path $sqlFilename -Value "Alter user $($poolCreds.username) identified by '$($poolCreds.password)';"}        
    }

    if ($yjb_pool){
        $poolXml = $installed_drive + $platformEnv.cv_yjb_xml
        $poolXmlFile = [xml](Get-Content -Path $poolXml)

        $poolCreds=$WebTierApexEnv.oracleDB.creds | where-object use -eq "tomcatYJBPool"

        $node = $poolXmlFile.Server.GlobalNamingResources.resource | where-object name -eq $poolCreds.poolName
        $node.username = $poolCreds.username
        $node.password = $poolCreds.password
        $node.url = "jdbc:oracle:thin:@//" + $WebTierApexEnv.oracleDB.HOST + ":" + $WebTierApexEnv.oracleDB.PORT + "/" + $WebTierApexEnv.oracleDB.SID
        $poolXmlFile.Save($poolXml)
        LogWrite "Updated $poolXml with credentials for $($poolCreds.username)" -logout
        if ($output_orasql) {Add-Content -Path $sqlFilename -Value "Alter user $($poolCreds.username) identified by '$($poolCreds.password)';"}        
    }

}

Export-ModuleMember -Function tomcat_pool_update

function Install_jdk
{
    Param (
        $installed_drive,
        $Product,
        $jdkPacks,
        $Package
        )
    LogWrite "JDK Check/Installation for : $($product.jdk_required)" -logout -logwarn
    
    foreach ($JDKInstall in $Product.jdk_required){
        $jdkDetails = $jdkPacks | where-object Type -eq $JDKInstall
        if (test-path "$installed_drive\$($jdkDetails.jdkhome)\bin\java.exe"){
            LogWrite "$($JDKInstall.type) - Already installed - Skipping" -logout  
        } else {
            $jdkDest=$installed_drive + $jdkDetails.jdkhome
            LogWrite "Unzipping $($jdkDetails.type) to $jdkDest" -logout  
            unzip "$Package\$($jdkDetails.packname)" $jdkdest

        }

        $jdkDetails

    }
}

Export-ModuleMember -Function Install_jdk

$java_jdk_pack="$basedir\package\jdk1.8.0_402.zip"
$java_jdk_version="1.8u402"


function Upgrade_Metabase {
    Param (
        $software_pack
    )

    # Extract file names from XML
    $metabase_file = ($software_pack | Where-Object { $_.name -eq "Metabase JAR" }).file
    $jdk_zip_file  = ($software_pack | Where-Object { $_.name -eq "Metabase JDK" }).file

    # Fallback if XML parsing fails- updated with zip files names located inside the package folder
    #if (-not $metabase_file -or $metabase_file -eq "") { $metabase_file = "metabase.zip" }
    #if (-not $jdk_zip_file -or $jdk_zip_file -eq "") { $jdk_zip_file = "jdk21.0.8_9.zip" }

    $metabase_path = Join-Path $package $metabase_file
    $jdk_zip       = Join-Path $package $jdk_zip_file

    # Validate files
    if (-not (Test-Path $metabase_path)) { LogWrite "Missing Metabase file: $metabase_path" -logfail -logout; exit }
    if (-not (Test-Path $jdk_zip)) { LogWrite "Missing JDK ZIP: $jdk_zip" -logfail -logout; exit }

    # Locate installation root
    $install_path = "CACI\WebTier\Java\metabase"
    $install_roots = find_installation_roots $install_path -include_c
    if ($install_roots.count -eq 0) { LogWrite "Metabase root not found. Exiting." -logfail -logout; exit }

    # Build paths
    $metabase_root = Join-Path $install_roots.DeviceID $install_path
    $jdk_target    = Join-Path $metabase_root "jdk"
    $metabase_jar_target = Join-Path (Join-Path $install_roots.DeviceID "CACI\WebTier\portals\prod\metabase") "metabase.jar"
    $serviceName = "metabase-prod"

    LogWrite "Checks passed. Proceeding with upgrade..." -logout

    # Stop service using CIM
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'"
    if ($service -and $service.State -eq 'Running') {
        LogWrite "Stopping service '$serviceName'" -loginfo -logout
        $service | Invoke-CimMethod -Name StopService | Out-Null
        Start-Sleep -Seconds 10
    }

    # Backup old JDK
    $jdk_backup = "${jdk_target}_old"
    if (Test-Path $jdk_backup) { Remove-Item $jdk_backup -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $jdk_target) {
        try { Rename-Item $jdk_target $jdk_backup -ErrorAction Stop }
        catch {
            LogWrite "JDK in use. Aborting upgrade." -logfail -logout
            $service | Invoke-CimMethod -Name StartService | Out-Null
            exit
        }
    }

    # Ensure folder exists
    if (-not (Test-Path $jdk_target)) { New-Item -ItemType Directory -Path $jdk_target | Out-Null }

    # Unpack JDK
    LogWrite "Unpacking JDK from $jdk_zip..." -loginfo
    Expand-Archive -Path $jdk_zip -DestinationPath $jdk_target -Force

    # Deploy Metabase JAR
    LogWrite "Deploying Metabase from $metabase_path..." -loginfo
    if ($metabase_path.ToLower().EndsWith(".zip")) {
        $tempExtractPath = Join-Path (Split-Path $metabase_path -Parent) "metabase_extract"
        if (Test-Path $tempExtractPath) { Remove-Item $tempExtractPath -Recurse -Force }
        Expand-Archive -Path $metabase_path -DestinationPath $tempExtractPath -Force

        $extractedJar = Join-Path $tempExtractPath "metabase.jar"
        if (-not (Test-Path $extractedJar)) {
            LogWrite "Metabase JAR not found in ZIP. Aborting." -logfail -logout
            exit
        }
        Copy-Item -Path $extractedJar -Destination $metabase_jar_target -Force
        Remove-Item $tempExtractPath -Recurse -Force
    } else {
        Copy-Item -Path $metabase_path -Destination $metabase_jar_target -Force
    }

    # Restart service using CIM
    LogWrite "Restarting service '$serviceName'" -loginfo -logout
    $service | Invoke-CimMethod -Name StartService | Out-Null
    Start-Sleep -Seconds 10

    # Verify service status
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'"
    if ($service.State -ne 'Running') {
        LogWrite "Service failed to start. Rolling back..." -logwarn -logout
        if (Test-Path $jdk_target) { Remove-Item $jdk_target -Recurse -Force }
        if (Test-Path $jdk_backup) { Rename-Item $jdk_backup $jdk_target }
        $service | Invoke-CimMethod -Name StartService | Out-Null
        LogWrite "Rollback complete." -loginfo
    } else {
        LogWrite "Metabase upgrade completed successfully." -loginfo
    }

    # Cleanup backup
    if (Test-Path $jdk_backup) { Remove-Item $jdk_backup -Recurse -Force -ErrorAction SilentlyContinue }
}
Export-ModuleMember -Function Upgrade_Metabase