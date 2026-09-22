# RDBMS networking functions
#
Function restart_listener
{
  Param (
    $listener_service='OracleOraDB19Home1TNSListener'
  )

 LogWrite "Restarting Service $listener_service" -loginfo
 if (Get-service $listener_service -ErrorAction SilentlyContinue) {
    restart-service -name $listener_service
 } else {
    LogWrite "Listener service $listener_service not found" -loginfo
 }
}
Export-ModuleMember -Function restart_listener

Function replace_sqlnet_file
{
  Param (
    [Parameter(Mandatory)]
    $oracle_db
  )

  run_defaults $oracle_db

  if ($oracle_db.containsKey('ORACLE_HOME')) {
      LogWrite "Replacing SQLNET.ORA file" -loginfo
      if (Test-Path $oracle_db.SQLNET_FILE){
        LogWrite "Removing old sqlnet.ora file for replacement :$($oracle_db.SQLNET_FILE)" -loginfo
        Remove-Item -Path $oracle_db.SQLNET_FILE -Force -ErrorAction SilentlyContinue| Out-Null
      } else {
        LogWrite "File does not exist : $($oracle_db.SQLNET_FILE)" -loginfo
      }
      Copy-Item $oracle_db.SQLNET_TEMPLATE -Destination $oracle_db.SQLNET_FILE -Force -ErrorAction SilentlyContinue| Out-Null
      LogWrite "SQLNET.ORA file replaced." -loginfo
  } else {
    LogWrite "Oracle Home not set" -logwarn -logout
  }
}
Export-ModuleMember -Function replace_sqlnet_file

Function check_add_tnsnames_entry
{
  Param (
    [Parameter(Mandatory)]
    $oracle_db,
    [switch]$replace_tnsnames_file
  )
  LogWrite "Check and add TNSNAMES entry" -loginfo

  run_defaults $oracle_db

  if ($oracle_db.containsKey('ORACLE_HOME')) {
    LogWrite "Oracle Home set to : $($oracle_db.ORACLE_HOME)" -loginfo

    LogWrite "TNSNames File details" -loginfo
    LogWrite "`tTNSNames File :$($oracle_db.TNSNAMES_FILE)" -loginfo
    LogWrite "`tTNSNames Template :$($oracle_db.TNSNAMES_TEMPLATE)" -loginfo
    LogWrite "`tTNSNames Entry :$($oracle_db.TNSNAMES_ENTRY)" -loginfo

    if ($replace_tnsnames_file) {
      LogWrite "Removing old tnsnames file for replacement :$($oracle_db.TNSNAMES_FILE)" -loginfo
      Remove-Item -Path $oracle_db.TNSNAMES_FILE -Force -ErrorAction SilentlyContinue| Out-Null
    }

    if (Test-Path $oracle_db.TNSNAMES_FILE){
      LogWrite "TNSNames File exists" -loginfo
      $tns_file = get-content -Raw $oracle_db.TNSNAMES_FILE
    } else {
      LogWrite "No TNSNames File, using template" -loginfo
      $tns_file = get-content -Raw $oracle_db.TNSNAMES_TEMPLATE
    }

    LogWrite "Processing placeholder substitutions" -loginfo
    $sub_details = file_sub_setup

    $tns_file = subs_file $tns_file $sub_details

    if (($tns_file.replace(' ','')).contains("(SERVICE_NAME=$($oracle_db.SID)")) {
        LogWrite "TNSNames file already has an entry for this database : $($oracle_db.SID)" -loginfo
    } else {
        LogWrite "Adding TNSNAMES entry for database : $($oracle_db.SID)" -loginfo
        $entry_file = subs_file (get-content -Raw $oracle_db.TNSNAMES_ENTRY) $sub_details
        $tns_file = "$tns_file`n$entry_file"
    }

    LogWrite "Writing : $($oracle_db.TNSNAMES_FILE)" -loginfo
    set-content -Path $oracle_db.TNSNAMES_FILE -Value $tns_file



  } else {
    LogWrite "Oracle Home not set" -logwarn -logout
  }

}
Export-ModuleMember -Function check_add_tnsnames_entry

Function check_add_listner_entry
{
  Param (
    [Parameter(Mandatory)]
    $oracle_db,
    [switch]$replace_listener_file
  )
  LogWrite "Check and add LISTENER entry" -loginfo

  run_defaults $oracle_db

  if ($oracle_db.containsKey('ORACLE_HOME')) {
    LogWrite "Oracle Home set to : $($oracle_db.ORACLE_HOME)" -loginfo


    LogWrite "Listener File details" -loginfo
    LogWrite "`tListener File :$($oracle_db.LISTENER_FILE)" -loginfo
    LogWrite "`tListener Template :$($oracle_db.LISTENER_TEMPLATE)" -loginfo
    LogWrite "`tListener Entry :$($oracle_db.LISTENER_ENTRY)" -loginfo

    if ($replace_listener_file) {
      LogWrite "Removing old listener file for replacement :$($oracle_db.LISTENER_FILE)" -loginfo
      Remove-Item -Path $oracle_db.LISTENER_FILE -Force -ErrorAction SilentlyContinue| Out-Null
    }

    if (Test-Path $oracle_db.LISTENER_FILE){
      LogWrite "Listener File exists" -loginfo
      $list_file = get-content -Raw $oracle_db.LISTENER_FILE
    } else {
      LogWrite "No Listener File, using template" -loginfo
      $list_file = get-content -Raw $oracle_db.LISTENER_TEMPLATE
    }

    LogWrite "Processing placeholder substitutions" -loginfo
    $sub_details = file_sub_setup

    $list_file = subs_file $list_file $sub_details


    if ($list_file.contains("GLOBAL_DBNAME = $($oracle_db.SID)")) {
        LogWrite "Listener file already has an entry for this database : GLOBAL_DBNAME = $($oracle_db.SID)" -loginfo
    } else {
        LogWrite "Adding listener entry for database : $($oracle_db.SID)" -loginfo
        $entry_file = subs_file (get-content -Raw $oracle_db.LISTENER_ENTRY) $sub_details
        $list_file = $list_file.replace("(SID_LIST =","(SID_LIST =`n$entry_file")
    }

    LogWrite "Writing : $($oracle_db.LISTENER_FILE)" -loginfo
    set-content -Path $oracle_db.LISTENER_FILE -Value $list_file


  } else {
    LogWrite "Oracle Home not set" -logwarn -logout
  }

}
Export-ModuleMember -Function check_add_listner_entry

Function subs_file
{
  Param (
    [Parameter(Mandatory)]
    $sub_file,
    [Parameter(Mandatory)]
    $sub_hash
  )

  foreach ($subit in $sub_hash.GetEnumerator()) {
    LogWrite "`tReplacing place holder : $($subit.name) with : $($subit.Value)" -loginfo
    $sub_file = $sub_file.replace("[$($subit.Name)]", $subit.Value)
  }

  return $sub_file
}

Function file_sub_setup
{
  Param (
    [hashtable]$sub_details = @{}
  )
  $sub_details.Add('ORACLE_HOME',$oracle_db.ORACLE_HOME)
  $sub_details.Add('ORACLE_SID',$oracle_db.SID)
  $sub_details.Add('LISTENER_PORT',$oracle_db.LISTENER_PORT)
  $sub_details.Add('TNSNAMES_PORT',$oracle_db.TNSNAMES_PORT)
  $sub_details.Add('FQHN',$oracle_db.FQHN)


  return $sub_details
}
# Services identification powershell functions
# Read in the service_ident.xml definition file

Function default_field
{
  Param (
    [Parameter(Mandatory)]
    $oracle_db,
    [Parameter(Mandatory)]
    $field_check,
    [Parameter(Mandatory)]
    $field_default
  )
if (-not $oracle_db.containsKey($field_check)) {
  $oracle_db.Add($field_check,$field_default)
  LogWrite "`t$field_check not set defaulting to $field_default" -loginfo
}

return $oracle_db
}

Function run_defaults
{
  Param (
    [Parameter(Mandatory)]
    $oracle_db
  )


  # If NEW home set, update to the New Home settings
  if ($oracle_db.containsKey('NEW_HOME')) {
    LogWrite "NEW_HOME Set" -loginfo
    LogWrite "`tORACLE_HOME : $($oracle_db.ORACLE_HOME)" -loginfo
    LogWrite "`tSet to : $($oracle_db.NEW_HOME)" -loginfo
    $oracle_db.ORACLE_HOME=$oracle_db.NEW_HOME
  }

  # General Defaults
  $FQHN = [System.Net.Dns]::GetHostByName($env.computerName).Hostname
  $oracle_db = default_field $oracle_db 'FQHN' $FQHN

  # Defaults for Database home/SID/Port
  $oracle_db = default_field $oracle_db 'ORACLE_HOME' "C:\CACI\DBTier\product\19.3.0\dbhome_1"
  $oracle_db = default_field $oracle_db 'SID' "CVPROD01"
  $oracle_db = default_field $oracle_db 'ORACLE_PORT' "1521"

  # Defaults for Listener settings
  $oracle_db = default_field $oracle_db 'LISTENER_FILE' "$($oracle_db.ORACLE_HOME)\network\admin\listener.ora"
  $oracle_db = default_field $oracle_db 'LISTENER_TEMPLATE' "$basedir\resource\listener.template"
  $oracle_db = default_field $oracle_db 'LISTENER_ENTRY' "$basedir\resource\listener.entry"
  $oracle_db = default_field $oracle_db 'LISTENER_PORT' $oracle_db.ORACLE_PORT


  # Defaults for TNSNAMES settings
  $oracle_db = default_field $oracle_db 'TNSNAMES_FILE' "$($oracle_db.ORACLE_HOME)\network\admin\tnsnames.ora"
  $oracle_db = default_field $oracle_db 'TNSNAMES_TEMPLATE' "$basedir\resource\tnsnames.template"
  $oracle_db = default_field $oracle_db 'TNSNAMES_ENTRY' "$basedir\resource\tnsnames.entry"
  $oracle_db = default_field $oracle_db 'TNSNAMES_PORT' $oracle_db.ORACLE_PORT

  # Defaults for SQLNET settings
  $oracle_db = default_field $oracle_db 'SQLNET_FILE' "$($oracle_db.ORACLE_HOME)\network\admin\sqlnet.ora"
  $oracle_db = default_field $oracle_db 'SQLNET_TEMPLATE' "$basedir\resource\sqlnet.ora"



}
Export-ModuleMember -Function run_defaults


Function oracle_sql
{
   Param (
     [Parameter(Mandatory)]
     $oracle_db,
     [string]$scriptfile_sql,
	 [string]$working_dir,
     $substitute,
	 [string]$oracle_creds='/ as sysdba'
  )
  Push-Location $working_dir
  if ($PSBoundParameters.ContainsKey('substitute')) {
    file_substitue $scriptfile_sql "sub_$scriptfile_sql" $substitute
    $scriptfile_sql = "sub_$scriptfile_sql"
  }

  $sqlplus_cmd = "echo exit | sqlplus -s $oracle_creds @" + $scriptfile_sql
  LogWrite "SQLPLus: $($sqlplus_cmd)" -loginfo
  $env:ORACLE_HOME=$oracle_db.ORACLE_HOME
  $env:JAVA_HOME=$oracle_db.ORACLE_HOME + '\jdk'
  $env:ORACLE_SID=$oracle_db.SID
  $env:PATH="$($oracle_db.ORACLE_HOME)\bin;$($oracle_db.ORACLE_HOME)\jdk\bin;" + $env:PATH

  $sql_out = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $sqlplus_cmd
  $sql_out = $sql_out | ? {$_ -ne ""}
  Pop-Location
  return $sql_out
}

Export-ModuleMember -Function oracle_sql

Function oracle_rman
{
   Param (
     [Parameter(Mandatory)]
     $oracle_db,
     [string]$scriptfile_rman,
   	 [string]$working_dir,
     $substitute 
   )
  Push-Location $working_dir

  if ($PSBoundParameters.ContainsKey('substitute')) {
    file_substitue "$($resource)\$($scriptfile_rman)" "sub_$($scriptfile_rman)" $substitute
    $scriptfile_rman = "sub_$scriptfile_rman"
    }

  $rman_cmd = "echo exit | rman  target / CMDFILE=" + $scriptfile_rman
  LogWrite "RMAN: $($rman_cmd)" -loginfo
  $env:NLS_DATE_FORMAT="dd/mm/rr hh24:mi"
  $env:ORACLE_HOME=$oracle_db.ORACLE_HOME
  $env:JAVA_HOME=$oracle_db.ORACLE_HOME + '\jdk'
  $env:ORACLE_SID=$oracle_db.SID
  $env:PATH="$($oracle_db.ORACLE_HOME)\bin;$($oracle_db.ORACLE_HOME)\jdk\bin;" + $env:PATH
  
  $rman_out = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $rman_cmd
  Pop-Location
  return $rman_out
}

Export-ModuleMember -Function oracle_rman

function file_substitue
{
   Param (
     [Parameter(Mandatory)]
     [string]$source_file,
     [Parameter(Mandatory)]
     [string]$target_file,
     [Parameter(Mandatory)]
     $substitutions
   )
    LogWrite "Substitution: $($source_file)" -loginfo
    $in_file = Get-Content "$($source_file)"

    $substitutions.GetEnumerator() | ForEach-Object {
        $in_file = $in_file -replace $_.Name, $_.Value
    }

    Set-Content -Path $target_file -Value $in_file
}

function rman_backup_std
{
   Param (
     [Parameter(Mandatory)]
     $oracle_db,
     [Parameter(Mandatory)]
     $backup_tag
    )

# Check FRA is set and valid
$ret_sql = oracle_sql $oracle_db q_fra_location.sql $resource

$sql_json = convertfrom-json -Inputobject "$ret_sql"
$oracle_db.Add('q_FRA',$sql_json.db_recovery_file_dest)

if (($oracle_db.q_FRA -ne "unset") -and (Test-Path $db_details.q_FRA)) {
    LogWrite "FRA location set to : $($oracle_db.q_FRA)" -loginfo

    # Database backup
    LogWrite "Performing database backup - system will be unavailable for the duration" -logout -logwarn
    $rman_subs = @{"#bcktag"="$backup_tag"} # Upper case only.

    $ret_rman = oracle_rman $db_details rman_std_backup.rman $resource $rman_subs

    # Check backup completed
    $ret_sql = oracle_sql $db_details q_db_backup.sql $resource $rman_subs

    if ($ret_sql.count -gt 0) {


    } else {
        LogWrite "Unable to validate backup completed successfully."  -logwarn -logout
        LogWrite -errid "abend" -logout;
        exit

    }


} else {
    LogWrite "Backup location - $($db_details.q_FRA) does not exist."  -logwarn -logout
    LogWrite -errid "abend" -logout;
    exit
}
}

Export-ModuleMember -Function rman_backup_std


function check_db
{
  Param (
    $oracle_db,
    [switch]$display_db
  )
  LogWrite "Database Check" -loginfo
#  $db_sid = $oracle_db.node.name
#  $db_home = $oracle_db.Node.SelectNodes("folders/folder[@type='ORACLE_HOME']/text()").value
#  $db_datafiles = $oracle_db.Node.SelectNodes("folders/folder[@type='DB_DATAFILES']/text()").value
#  $db_datafiles_freespace = $oracle_db.Node.SelectNodes("folders/folder[@type='DB_DATAFILES']").freespace
#  $db_FRA = $oracle_db.Node.SelectNodes("folders/folder[@type='DB_FRA']/text()").value
#  $db_FRA_freespace = $oracle_db.Node.SelectNodes("folders/folder[@type='DB_FRA']").freespace
  $db_sid = $oracle_db.SID
  $db_home = $oracle_db.ORACLE_HOME
  $db_home_freespace = $oracle_db.ORACLE_HOME_FREESPACE
  $db_base = $oracle_db.ORACLE_BASE
  $db_datafiles = $oracle_db.DATAFILES
  $db_datafiles_freespace = $oracle_db.DATAFILES_FREESPACE
  $db_FRA = $oracle_db.FRA
  $db_FRA_freespace = $oracle_db.FRA_FREESPACE
  if ($display_db) {show_db}

}

Export-ModuleMember -Function check_db

function show_db
{
  LogWrite "Database detals" -loginfo
  LogWrite "  SID : $db_sid" -loginfo -logout
  LogWrite "  Home : $db_home" -loginfo -logout
  $db_free=[math]::Round($db_home_freespace/1048576,2)
  LogWrite "    Free Space (MB) : $db_free" -loginfo -logout
  LogWrite "  Base : $db_base" -loginfo -logout
  LogWrite "  Datafiles :  $db_datafiles" -loginfo -logout
  $df_free=[math]::Round($db_datafiles_freespace/1048576,2)
  LogWrite "     Free Space (MB):  $df_free" -loginfo -logout
  LogWrite "  FRA : $db_FRA" -loginfo -logout
  $fra_free=[math]::Round($db_FRA_freespace/1048576,2)
  LogWrite "     Free Space (MB): $fra_free" -loginfo -logout
}


function db_homes_findall
{
   LogWrite "Looking for Database homes on server" -loginfo
   $disks = get-ciminstance win32_logicaldisk -Filter "DriveType='3'"
   $avail = $disks | ? { $_.DeviceID -notmatch "[abz]:"}
   $found_home=@()
   foreach ($drive in $avail){
       $dbtier="$($drive.DeviceID)\CACI\DBTier\product"
       logwrite "Searching in $dbtier" -loginfo
       $found_dirs= Get-childitem -path $dbtier -recurse -filter "*dbhome_*" -directory -ErrorAction SilentlyContinue
       logwrite "Found Dirs  $found_dirs" -loginfo
       foreach ($dirhit in $found_dirs) { 
        LogWrite "     Dir hit : $($dirhit.FullName)" -logout -loginfo
        $found_home+=$dirhit.fullname
        }
   }
    logwrite "Found $($found_home.count) homes" -logout -loginfo
    return $found_home
}

Export-ModuleMember -Function db_homes_findall

function db_service_findall
{
  Param (
    $home_list
  )
  $home_details=@()
  foreach ($dbhome in $home_list) {
  #  $db_services = Get-CimInstance -ClassName win32_service | ?{$_.PathName -like "*$($dbhome)*"}
    $homes_esc = $dbhome.replace('\','\\')
    $db_services = Get-CimInstance -Query "SELECT * from Win32_service WHERE PathName LIKE '$($homes_esc)%'" | Select-Object Name,State
    
    logwrite "Home : $dbhome" -logout -loginfo
    logwrite "Services : $db_services" -logout -loginfo
#    foreach ($svc in $db_services) {
#        $home_details+=(@{"Home"="$dbhome" ;"Services"="$($svc.Name)"; "state"="$($svc.state)"})
#    }
     $home_details+=(@{"Home"="$dbhome" ;"Servcnt"="$($db_services.count)"})
  }
  return $home_details
}

Export-ModuleMember -Function db_service_findall

function db_deinstall
{
  Param (
    $db_home
  )

  # Attempt move to check for file access
  $discard = Rename-Item $db_home "$($db_home)_removing" -ErrorAction SilentlyContinue  

  # Remove renamed folder

  if (test-path $db_home) {
    logwrite "Unable to remove, file in use in $db_home" -logwarn -logout

  } else {
    $discard = Remove-Item -Path "$($db_home)_removing" -Force -Recurse -ErrorAction SilentlyContinue
    logwrite "Home removed $db_home" -loginfo -logout
  }

}

Export-ModuleMember -Function db_deinstall

function remove_OracleRemExecServiceV2
{

  $chk_service = get-service -name 'OracleRemExecServiceV2' -ErrorAction SilentlyContinue

  if ($chk_service) {
  logwrite "Prior service OracleRemExecServiceV2 exists. Removing" -logwarn

    if ($chk_service.CanStop) {$chk_service.stop}

     # PS 6.0 $chk_service | remove-service -Whatif
    $service = Get-Ciminstance -ClassName Win32_Service -Filter "Name='$($chk_service.name)'"
    $service | Remove-Ciminstance
    }

}

Export-ModuleMember -Function remove_OracleRemExecServiceV2



$db_sid
$db_home
$db_home_freespace
$db_datafiles
$db_datafiles_freespace
$db_FRA
$db_FRA_freespace