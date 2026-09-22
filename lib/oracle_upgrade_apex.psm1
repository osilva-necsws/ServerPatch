# Install Oracle Home

# Add in unzip function
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}
Function check_and_extract_pack
{
  Param (
    [Parameter(Mandatory)]
    $db_details
  )
  LogWrite "Upacking component software (avg 2 minutes elapse)" -logout
  $apex_path="$($db_details.ORACLE_BASE)\upgrade\19c\apex"
  $db_details.Add('APEX_SOURCE',$apex_path)
  LogWrite "Removing Apex software at $apex_path" -loginfo

  Remove-Item -Path $apex_path -Force -Recurse -ErrorAction SilentlyContinue| Out-Null
  new-item -path $apex_path -itemType directory -ErrorAction SilentlyContinue| Out-Null

  LogWrite "Extracting Apex software $oracle_apex_pack to $apex_path" -loginfo
  unzip $oracle_apex_pack $apex_path

  $ords_path="$($db_details.ORACLE_BASE)\upgrade\19c\ords"
  $db_details.Add('ORDS_SOURCE',$ords_path)
  LogWrite "Removing ORDS software at $ords_path" -loginfo

  Remove-Item -Path $ords_path -Force -Recurse -ErrorAction SilentlyContinue| Out-Null
  new-item -path $ords_path -itemType directory -ErrorAction SilentlyContinue| Out-Null

  LogWrite "Extracting ORDS software $oracle_ords_pack to $ords_path" -loginfo
  unzip $oracle_ords_pack $ords_path


  return $db_details
}

Function generate_apex_cmd
{
  Param (
    [Parameter(Mandatory)]
    $db_details
  )
  if (-not $db_details.containsKey('IMAGE_PREFIX')) {
    LogWrite "Image Prefix unset, using SID to extrapolate" -loginfo
    switch ($($db_details.SID).substring(0,6)) {
      "CVPROD" {$apex_suffix='/prod/'}
      "CVTEST" {$apex_suffix='/test/'}
      "CVTRAI" {$apex_suffix='/train/'}
      default {$apex_suffix='/prod/'}
    }
  } else {
    LogWrite "Image Prefix set, using component_ident.xml setting - $($db_details.IMAGE_PREFIX)" -loginfo
    $apex_suffix = $db_details.IMAGE_PREFIX
  }

  LogWrite "Image Prefix is $apex_suffix" -loginfo

  $oracle_apex_cmd="@apexins $oracle_apex_install_tablespace $oracle_apex_install_tablespace $oracle_temporary_tablespace $apex_suffix"
  $oracle_ords_scripts="$($db_details.ORACLE_BASE)\upgrade\19c\ords\scripts"

  $db_details.Add('APEX_CMD',"echo exit | sqlplus / as sysdba $oracle_apex_cmd")
  $db_details.Add('APEX_CMD_AUX',"echo exit | sqlplus / as sysdba @apex_rest_config.sql")
  $db_details.Add('APEX_CMD_TIDY',"sqlplus / as sysdba @apex_tidy.sql")
  $db_details.Add('INSTALLER_PKG_CMD',"echo exit | sqlplus / as sysdba @IMPULSE_CV_INSTALLER_PKG.sql")
  $db_details.Add('TRIGGERS_CMD',"echo exit | sqlplus / as sysdba @DISABLE_ALL_TRIGGERS.sql")
  $db_details.Add('COMPAT_CMD',"echo exit | sqlplus / as sysdba @set_compatability.sql")
  $db_details.Add('ORDS_CMD',"echo exit | sqlplus / as sysdba @$oracle_ords_scripts\install\core\ords_manual_install '$($log_path)\' $oracle_apex_install_tablespace $oracle_temporary_tablespace $oracle_apex_install_tablespace $oracle_temporary_tablespace '$oracle_ords_scripts'")


  return $db_details
}

Function execute_upgrade
{
  Param (
    [Parameter(Mandatory)]
    $db_details
  )

  LogWrite "Upgrading component software (1/4)  (avg 12 minutes elapse)" -logout

  $env:ORACLE_HOME=$db_details.ORACLE_HOME
  $env:JAVA_HOME=$db_details.ORACLE_HOME + '\jdk'
  $env:ORACLE_SID=$db_details.SID
  $env:PATH="$($db_details.ORACLE_HOME)\bin;$($db_details.ORACLE_HOME)\jdk\bin;" + $env:PATH


  LogWrite "Changing WD to folder : $($db_details.APEX_SOURCE)" -loginfo
  LogWrite "In Oracle Home : $($db_details.ORACLE_HOME)" -loginfo
  Push-Location "$($db_details.APEX_SOURCE)\apex"

  LogWrite "Command: $($db_details.APEX_CMD)" -loginfo
  $apex_out = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $db_details.APEX_CMD

  Add-content $oracle_apex_log -value "START == Apex Upgrade Log"
  foreach ($apex_line in $apex_out) {Add-content $oracle_apex_log -value $apex_line}
  Add-content $oracle_apex_log -value "END == Apex Upgrade Log"

  if ($apex_out -match $oracle_apex_success) {
        LogWrite "Component upgrade (1/4) success" -loginfo
    } else {
        LogWrite "Component upgrade (1/4) has failed" -logwarn -logout
        LogWrite -errid "abend" -logout;
    exit
    }

  LogWrite "Upgrading component software (2/4)" -logout
  LogWrite "Command: $($db_details.APEX_CMD_AUX)" -loginfo
  $apex_out = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $db_details.APEX_CMD_AUX

  Add-content $oracle_apex_log -value "START == Apex REST Schemas Log"
  foreach ($apex_line in $apex_out) {Add-content $oracle_apex_log -value $apex_line}
  Add-content $oracle_apex_log -value "END == Apex REST Schemas Log"

  if ($apex_out -match $oracle_rest_success) {
        LogWrite "Component upgrade (2/4) success" -loginfo
    } else {
        LogWrite "Component upgrade (2/4) has failed" -logwarn -logout
        LogWrite -errid "abend" -logout;
    exit
    }

    LogWrite "Upgrading component software (3/4) (avg 2 minutes elapse)" -logout

    LogWrite "Changing WD to folder : $resource" -loginfo
    LogWrite "In Oracle Home : $($db_details.ORACLE_HOME)" -loginfo
    Push-Location $resource

    LogWrite "Command: $($db_details.APEX_CMD_TIDY) Output logged: $oracle_apex_log" -loginfo
    $apex_out = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $db_details.APEX_CMD_TIDY

    Add-content $oracle_apex_log -value "START == Apex Tidy up Log"
    foreach ($apex_line in $apex_out) {Add-content $oracle_apex_log -value $apex_line}
    Add-content $oracle_apex_log -value "END == Apex Tidy up Log"
# Installer set up

    LogWrite "Command: $($db_details.INSTALLER_PKG_CMD) Output logged: $oracle_apex_log" -loginfo
    $sql_out = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $db_details.INSTALLER_PKG_CMD

    Add-content $oracle_apex_log -value "START == Installer Package deploy"
    foreach ($sql_line in $sql_out) {Add-content $oracle_apex_log -value $sql_line}
    Add-content $oracle_apex_log -value "END == Installer Package deploy"

    # Trigger disable

    LogWrite "Command: $($db_details.TRIGGERS_CMD) Output logged: $oracle_apex_log" -loginfo
    $sql_out = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $db_details.TRIGGERS_CMD

    Add-content $oracle_apex_log -value "START == Trigger disable"
    foreach ($sql_line in $sql_out) {Add-content $oracle_apex_log -value $sql_line}
    Add-content $oracle_apex_log -value "END == Trigger disable"

      # Set set_compatability

    LogWrite "Command: $($db_details.COMPAT_CMD) Output logged: $oracle_apex_log" -loginfo
    $sql_out = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $db_details.COMPAT_CMD

    Add-content $oracle_apex_log -value "START == Compatability set and restart"
    foreach ($sql_line in $sql_out) {Add-content $oracle_apex_log -value $sql_line}
    Add-content $oracle_apex_log -value "END == Compatability set and restart"

      # Run ORDS installation content into database

    LogWrite "Upgrading component software (4/4)" -logout

    LogWrite "Changing WD to folder : $($db_details.ORDS_SOURCE)" -loginfo
    LogWrite "In Oracle Home : $($db_details.ORACLE_HOME)" -loginfo
    Push-Location "$($db_details.ORDS_SOURCE)"

    LogWrite "Command: $($db_details.ORDS_CMD)" -loginfo
    $apex_out = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $db_details.ORDS_CMD

    Add-content $oracle_apex_log -value "START == ORDS Upgrade Log"
    foreach ($apex_line in $apex_out) {Add-content $oracle_apex_log -value $apex_line}
    Add-content $oracle_apex_log -value "END == ORDS Upgrade Log"

#   if ($apex_out -match $oracle_ords_success) {
#        LogWrite "Componenet upgrade (1/3) success" -loginfo
#    } else {
#          LogWrite "Componenet upgrade (1/3) has failed" -logwarn -logout
#          LogWrite -errid "abend" -logout;
#    exit
#    }
      Pop-Location #ORDS Folder


    Pop-Location #resaurce

  Pop-Location #main

Return $db_details
}

Function oracle_upgrade_apex
{
  Param (
    [Parameter(Mandatory)]
    $db_details
  )


   LogWrite "Starting Component upgrade for database : $($db_details.SID)" -logout
   $db_details = check_and_extract_pack $db_details # Remove 12c listener if it exists
   $db_details = generate_apex_cmd $db_details
   $db_details = execute_upgrade $db_details
   LogWrite "Completed Component upgrade for database : $($db_details.SID)" -logout

   return $db_details
}

Export-ModuleMember -Function oracle_upgrade_apex

# Constants used in Apex and ORDS schema installations
$oracle_temporary_tablespace="TEMPORARY_DATA"
#$oracle_temporary_tablespace="TEMP"

$oracle_apex_install_tablespace="SYSAUX"

# Apex installation package - pack location and settings
$oracle_apex_pack="$basedir\package\apex_19.1_en_modified.zip"

$oracle_apex_image_prefix="/prod/"
$oracle_apex_logfile="upgrade_apex_$(get-date -f dd-MM-yyyy).log"
$oracle_apex_log=$log_path.ToString() + "\" + $oracle_apex_logfile
$oracle_apex_space=6501961728
#
$oracle_apex_success="Oracle Application Express is installed in the APEX_190100 schema."

$oracle_rest_success="PL/SQL procedure successfully completed."

# ORDS Installation package - pack location and settings
$oracle_ords_pack="$basedir\package\ords.zip"

# Testing overrides
#$oracle_apex_success="PL/SQL procedure successfully completed." # Testing override
