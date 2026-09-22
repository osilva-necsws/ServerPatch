# Install Oracle Home

# Add in unzip function
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

Function oracle_home_check
{
  Param (
    [Parameter(Mandatory)]
    $db_details,
    $software_pack
  )
   $oracle_home_suffix="\product\$($software_pack.version)\dbhome_1"
   $oracle_home_path="CACI\DBTier" + $oracle_home_suffix

   LogWrite "Checking for Database software installation" -logout
   LogWrite "`tSeaching for Oracle 19c home : $oracle_home_path" -loginfo

  $folder_loc = foldident_find  $oracle_home_path

   if ($folder_loc){
     LogWrite "`tLocated installation, skipping installation" -logout
     $found_home = $folder_loc.DeviceID + "\" + $oracle_home_path
     $db_details.Add('NEW_HOME',$found_home)
     LogWrite "`tFound Oracle Home at $found_home" -loginfo
   } else {
     LogWrite "Software installation required" -logout
   }
   return $db_details
}

Export-ModuleMember -Function oracle_home_check

Function generate_response_file
{
  Param (
    [Parameter(Mandatory)]
    $db_details,
    $oraCFG
  )
  LogWrite "Generating Software Home Response File : $($db_details.NEW_HOME_RESPONSE_FILE)" -loginfo
  LogWrite "`tRemoving old file" -loginfo

  $discard = Remove-Item -Path $db_details.NEW_HOME_RESPONSE_FILE -Force -ErrorAction SilentlyContinue

  LogWrite "`tGenerating file" -loginfo

  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "oracle.install.responseFileVersion=/oracle/install/rspfmt_dbinstall_response_schema_v19.0.0"
  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "oracle.install.option=INSTALL_DB_SWONLY"
  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "ORACLE_BASE=$($db_details.ORACLE_BASE)"
  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "oracle.install.db.InstallEdition=EE"
  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "oracle.install.db.config.starterdb.type=GENERAL_PURPOSE"
  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "oracle.install.db.ConfigureAsContainerDB=false"
  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "oracle.install.db.config.starterdb.memoryOption=false"
  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "oracle.install.db.config.starterdb.installExampleSchemas=false"
  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "oracle.install.db.config.starterdb.managementOption=DEFAULT"
  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "oracle.install.db.config.starterdb.omsPort=0"
  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "oracle.install.db.config.starterdb.enableRecovery=false"
  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "oracle.install.IsBuiltInAccount=true"
  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "oracle.install.IsVirtualAccount=false"
#  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "oracle.install.IsVirtualAccount=true"
#  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "oracle.install.OracleHomeUserName=`"$($oraCFG.caciORAUser)`""
#  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "oracle.install.OracleHomeUserPassword=`"$($oraCFG.caciORAPass)`""


  LogWrite "Response File complete" -loginfo
  return $db_details
}

Function oracle_home_setup
{
  Param (
    $db_details
  )
  LogWrite "Running Setup Command:" -loginfo

  $env:ORACLE_HOME=$db_details.NEW_HOME
  $env:PATH=$env:PATH + ";$($db_details.NEW_HOME)\bin"
  $env:JAVA_HOME=$webtier + '\Java\jdk'

  $run_cmd = "$($db_details.NEW_HOME_SETUP_CMD) -silent -noconfig -WaitForCompletion -responseFile $($db_details.NEW_HOME_RESPONSE_FILE)"
  LogWrite "Command: $run_cmd" -loginfo
  $discard = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $run_cmd
  return $db_details
}

Function oracle_install_new_home
{
  Param (
    $db_details,
    $software_pack,
    $new_base
  )

$oracle_db_pack="$basedir\package\$($software_pack.file)"
$oracle_home_space=$($software_pack.space)
$oracle_home_suffix="\product\$($software_pack.version)\dbhome_1"
$oracle_home_path="CACI\DBTier" + $oracle_home_suffix

# DR Run - Property settings
if (-not $db_details.containsKey('ORACLE_HOME')){
  $db_details.Add('ORACLE_HOME',$new_base + $oracle_home_path)  
  $oradir=$db_details.ORACLE_HOME
#  $filter = "DriveType=3 And Name='$($oradir -replace '\\', '\\')'"
  $freespace = (Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | where-object {$oradir -like "$($_.DeviceID)*"}).freespace
  $db_details.Add('ORACLE_HOME_FREESPACE',$freespace)  
  LogWrite "DR Run - Setting ORACLE_HOME to $($db_details.ORACLE_HOME) - Freespace $($db_details.ORACLE_HOME_FREESPACE)" -logwarn -logout
}

  If (!(Test-Path $oracle_db_pack)) {
    LogWrite "Database software missing" -logwarn -logout
    LogWrite "$oracle_db_pack not found" -logwarn -logout
    LogWrite -errid "abend" -logout;
    exit
  } # Test software pack included

   $db_details=oracle_home_check $db_details -software_pack:$software_pack

   if (-not $db_details.containsKey('NEW_HOME')){
     $home_str=$db_details.ORACLE_HOME -split "\\product"
     $new_home=$home_str[0] + $oracle_home_suffix
     LogWrite "Database Software Installation" -logout
     $req_space=[math]::Round($oracle_home_space/1073741824,2)
     $avail_space=[math]::Round($db_details.ORACLE_HOME_FREESPACE/1073741824,2)
     LogWrite "Checking Free space for DB Software" -logout
     LogWrite "Free : $avail_space gb - Required for Software : $req_space gb" -logout
     if ([int64]$db_details.ORACLE_HOME_FREESPACE -le [int64]$oracle_home_space){
       LogWrite "Insufficient space for Software installation" -logwarn -logout
       LogWrite "Installation requires $req_space gb free minimum" -logwarn -logout
       LogWrite -errid "abend" -logout;
       exit
     } # Test software pack included
    

     LogWrite "From pack : $oracle_db_pack" -loginfo
     LogWrite "To : $new_home" -loginfo

     LogWrite "Unpacking software distribution (avg 8 minutes elapse)" -logwarn -logout
     # Unzip installation pack to location
     unzip $oracle_db_pack $new_home

     If (!(Test-Path $new_home)) {LogWrite -errid "abend" -logout; exit} # Test extract has created the folder

     LogWrite "Software unpacked" -logout
     $db_details.Add('NEW_HOME',$new_home)
     $db_details.Add('NEW_HOME_JAVA',"$($db_details.NEW_HOME)\jdk")
     $db_details.Add('NEW_HOME_SETUP_CMD',"$($db_details.NEW_HOME)\setup.exe -J-XX:CompileCommand=exclude,java/lang/StringBuilder.append -J-XX:CompileCommand=exclude,java/lang/AbstractStringBuilder.append")
     $db_details.Add('NEW_HOME_RESPONSE_FILE',"$($db_details.NEW_HOME)\CACI_configure.rsp")

    
#     $db_configFolder = $db_details.ORACLE_BASE + '\config'
#     $db_configFile = $db_configFolder + '\dbConfig.xml'

#     if (test-path $db_configFile){
#      $oraCFG = Import-Clixml -Path $db_configFile
#     } else {
#      $caciORAPassrnd = "CACIoraSvc" + (-join ((65..90) + (97..122) | Get-Random -Count 5 | % {[char]$_}))
#      $oraCFG+=New-Object PsObject -property @{ caciORAUser = "caciORA1"; caciORAPass = $caciORAPassrnd}
#      new-item -ItemType Directory -force -Path $db_configFolder -ErrorAction SilentlyContinue | out-null
#      $oraCFG | Export-Clixml -Path $db_configFile -ErrorAction SilentlyContinue | out-null
#      LogWrite "Created Home config file : $db_configFile"
#     }

     $db_details = generate_response_file $db_details $oraCFG

     LogWrite "Configuring installation (avg 6 minutes elapse)" -logout
     $db_details = oracle_home_setup $db_details
     LogWrite "Installation and configuration completed." -logout

   } else {
     # New home set when current home found
     $db_details.Add('NEW_HOME_JAVA',"$($db_details.NEW_HOME)\jdk")
     $db_details.Add('NEW_HOME_SETUP_CMD',"$($db_details.NEW_HOME)\setup.exe -J-XX:CompileCommand=exclude,java/lang/StringBuilder.append -J-XX:CompileCommand=exclude,java/lang/AbstractStringBuilder.append")
	 # setup.exe -J-XX:CompileCommand=exclude,java/lang/StringBuilder.append -J-XX:CompileCommand=exclude,java/lang/AbstractStringBuilder.append
     $db_details.Add('NEW_HOME_RESPONSE_FILE',"$($db_details.NEW_HOME)\CACI_configure.rsp")
     LogWrite "Software found, Continuing..." -logout
   }

   return $db_details
}

Export-ModuleMember -Function oracle_install_new_home

