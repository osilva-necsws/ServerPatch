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
    $db_details
  )

   LogWrite "Checking for Database software installation" -loginfo -logout
   LogWrite "Seaching for Oracle 19c home : $oracle_home_path" -loginfo

  $folder_loc = foldident_find  $oracle_home_path

   if ($folder_loc){
     LogWrite "Located installation, skipping installation" -loginfo -logout
     $found_home = $folder_loc.DeviceID + "\" + $oracle_home_path
     $db_details.Add('NEW_HOME',$found_home)
     LogWrite "Found Oracle Home at $found_home" -loginfo
   } else {
     LogWrite "Software installation required" -loginfo -logout
   }
   return $db_details
}

Export-ModuleMember -Function oracle_home_check

Function register_db_networking
{
  Param (
    [Parameter(Mandatory)]
    $db_details
  )
  check_add_listner_entry $db_details
  check_add_tnsnames_entry  $db_details
  replace_sqlnet_file $db_details
  restart_listener
}
Export-ModuleMember -Function register_db_networking


Function generate_upgrade_file
{
  Param (
    [Parameter(Mandatory)]
    $db_details
  )
  LogWrite "Generating Upgrade Response File : $($db_details.UPGRADE_RESPONSE_FILE)" -loginfo
  LogWrite "Removing old file" -loginfo

  $discard = Remove-Item -Path $db_details.UPGRADE_RESPONSE_FILE -Force -ErrorAction SilentlyContinue

  LogWrite "Generating file" -loginfo


  Add-content $db_details.UPGRADE_RESPONSE_FILE -value "global.autoupg_log_dir=$($log_path.path.replace('\','\\'))"
#  Add-content $db_details.UPGRADE_RESPONSE_FILE -value "upg1.dbname=$($db_details.SID)"
  Add-content $db_details.UPGRADE_RESPONSE_FILE -value "upg1.start_time=NOW"
  Add-content $db_details.UPGRADE_RESPONSE_FILE -value "upg1.source_home=$($db_details.ORACLE_HOME.replace('\','\\'))"
  Add-content $db_details.UPGRADE_RESPONSE_FILE -value "upg1.target_home=$($db_details.NEW_HOME.replace('\','\\'))"
  Add-content $db_details.UPGRADE_RESPONSE_FILE -value "upg1.sid=$($db_details.SID)"
  Add-content $db_details.UPGRADE_RESPONSE_FILE -value "upg1.log_dir=$($log_path.path.replace('\','\\'))"
#  Add-content $db_details.NEW_HOME_RESPONSE_FILE -value "upg1.upgrade_node=node1"
#  Add-content $db_details.UPGRADE_RESPONSE_FILE -value "upg1.target_version= 19.1"


  LogWrite "Response File complete" -loginfo
  return $db_details
}

Function generate_dbca_file
{
  Param (
    [Parameter(Mandatory)]
    $db_details
  )
  LogWrite "Generating Upgrade Response File : $($db_details.DBCA_RESPONSE_FILE)" -loginfo
  LogWrite "Removing old file" -loginfo

  $discard = Remove-Item -Path $db_details.DBCA_RESPONSE_FILE -Force -ErrorAction SilentlyContinue

  LogWrite "Generating file" -loginfo


  Add-content $db_details.DBCA_RESPONSE_FILE -value "responseFileVersion=/oracle/assistants/rspfmt_dbca_response_schema_v19.0.0"
  Add-content $db_details.DBCA_RESPONSE_FILE -value "gdbName=CVPROD01"
  Add-content $db_details.DBCA_RESPONSE_FILE -value "sid=CVPROD01"



  LogWrite "Response File complete" -loginfo
  return $db_details
}

Function find_listeners
{
# $listeners = Get-WmiObject win32_service | Where-Object{$_.PathName -match "TNSLSNR"} | Select-Object name,pathname,state
$listeners = get-CimInstance  win32_service | Where-Object{$_.PathName -match "TNSLSNR"} | Select-Object name,pathname,state


return $listeners
}

function listener_for_home
{
  Param (
    [Parameter(Mandatory)]
    $db_details,
    [Parameter()]
    [switch]$remove_old
  )
$listeners = find_listeners
$check_path = "$($db_details.NEW_HOME)\BIN\TNSLSNR"

foreach($listener in $listeners) {
        LogWrite "Checking Listener service : $listener" 
        if ((join-path $listener.Pathname '') -eq (join-path $check_path '')) {
            LogWrite "Listener for home found : $listener" 
            $home_listener=$listener
        } else {
        if ($remove_old) {
            $listener_svr = Get-WmiObject win32_service | Where-Object{$_.DisplayName -match "$($listener.name)"}
            $discard = $listener_svr.StopService()
            $discard = $listener_svr.delete()
#            $discard = Get-service -DisplayName "$($listener.name)" | Stop-Service
#            $discard = Get-service -DisplayName "$($listener.name)" | Remove-Service
            LogWrite "Removed listener $($listener.Pathname)" -loginfo
            }
        }
    }

return $home_listener
}

function move_listener
{
  Param (
    [Parameter(Mandatory)]
    $db_details
  )
  # Stop and clean up old listener processes before removing old listener services
  LogWrite "Move Listener - Stopping old listener" -loginfo
  try {
    $env:ORACLE_HOME = $db_details.ORACLE_HOME
    $env:PATH = "$($db_details.ORACLE_HOME)\bin;" + $env:PATH
    LogWrite "Attempting to stop old listener with lsnrctl..." -loginfo
    & lsnrctl stop
  } catch {
    LogWrite "Failed to stop listener with lsnrctl: $($_.Exception.Message)" -logwarn
  }

  # Kill any remaining tnslsnr.exe processes for the old home
  try {
    # First attempt: Kill by path matching ORACLE_HOME
    $procs = Get-Process tnslsnr -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$($db_details.ORACLE_HOME)*" }
    foreach ($proc in $procs) {
      LogWrite "Killing lingering tnslsnr.exe by Path (PID: $($proc.Id))" -logwarn
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }

    # Second attempt: Check process listening on port 1521 (common cause of upgrade failure)
    $port = 1521
    LogWrite "Checking for processes holding port $port..." -loginfo
    $conns = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue 
    # Use array to avoid modifying collection while iterating
    $pidsToKill = $conns | Select-Object -ExpandProperty OwningProcess -Unique | Where-Object { $_ -gt 0 }
    
    foreach ($pidToKill in $pidsToKill) {
        $pname = (Get-Process -Id $pidToKill -ErrorAction SilentlyContinue).ProcessName
        LogWrite "Found process $pidToKill ($pname) holding port $port - Killing it" -logwarn
        
        # Try Stop-Process
        Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue
        
        # Try taskkill as backup (often more effective for zombies/access denied)
        LogWrite "Running taskkill /F /PID $pidToKill" -loginfo
        Start-Process -FilePath "taskkill.exe" -ArgumentList "/F /PID $pidToKill" -NoNewWindow -Wait -ErrorAction SilentlyContinue
    }
    
    # Wait a moment for ports to free up
    Start-Sleep -Seconds 2

    # Third attempt: Force close any remaining TCP connections (ghost connections)
    LogWrite "Checking for stubborn TCP connections on port $port..." -loginfo
    $stubbornConns = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if ($stubbornConns) {
        foreach ($conn in $stubbornConns) {
            LogWrite "Force closing TCP connection (PID: $($conn.OwningProcess), State: $($conn.State))" -logwarn
            # Reset the connection forcefully
            # Note: Remove-NetTCPConnection is available on Windows Server 2012 R2+ / Windows 8.1+
            try {
                # Force kill the owning process as well if Remove-NetTCPConnection isn't enough or available
                Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
                
                # Close the connection
                $conn | Remove-NetTCPConnection -Force -Confirm:$false -ErrorAction Stop
                LogWrite "  Successfully closed connection" -logwarn
            } catch {
                LogWrite "  Failed to close connection: $_" -logwarn
            }
        }
    }
    
    # Final wait
    Start-Sleep -Seconds 3
    
    # Wait a moment for ports to free up
    Start-Sleep -Seconds 5
  } catch {
    LogWrite "Error cleaning up listener processes: $($_.Exception.Message)" -logwarn
  }

  # Remove old listener services
  LogWrite "Move Listener - Removing old services" -loginfo
  $home_listener = listener_for_home $db_details -remove_old

  # Copy configuration from ORACLE_HOME to NEW_HOME
  LogWrite "Move Listener - Copying config from $($db_details.ORACLE_HOME) to $($db_details.NEW_HOME)"
  Copy-Item -Path "$($db_details.ORACLE_HOME)\network\admin\*.ora" -Destination "$($db_details.NEW_HOME)\network\admin" -Force  -ErrorAction SilentlyContinue| Out-Null
  start_listener $db_details
}

Function start_listener
{
  Param (
    [Parameter(Mandatory)]
    $db_details
  )
  $env:ORACLE_HOME=$db_details.NEW_HOME
  $env:JAVA_HOME=$db_details.NEW_HOME + '\jdk'
  $env:PATH="$($db_details.NEW_HOME)\bin;$($db_details.NEW_HOME)\jdk\bin;" + $env:PATH
  $listener_start="lsnrctl start"
  LogWrite "Issuing Startup command : $listener_start" -loginfo
  $listener_out = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $listener_start

  $listener = find_listeners
    # Set service start to automatic
  $discard = $listener | Set-Service -StartupType Automatic

}

Function execute_upgrade
{
  Param (
    [Parameter(Mandatory)]
    $db_details
  )

#Check theres a listener for this home
#  LogWrite "Checking for a listener for $($db_details.NEW_HOME))" -loginfo
#  $home_listener = listener_for_home $db_details

  if ($home_listener) {
    LogWrite "19c Home already exists - Using standard listener" -loginfo
    $dbua_listener="-listeners LISTENER"
    $dbua_listener=""
  } else {
    LogWrite "Migrating to new 19c listener - registering database with it" -loginfo
    $dbua_listener="-createlistener LISTENER:1521"
    move_listener $db_details
    $dbua_listener="-listeners LISTENER"
    $dbua_listener=""
  }

  $rman_path="$($db_details.FRA)_upgrade"

  new-item -path $rman_path -itemType directory -ErrorAction SilentlyContinue| Out-Null

  $db_configFolder = $db_details.ORACLE_BASE + '\config'
  $db_configFile = $db_configFolder + '\dbConfig.xml'

  if (test-path $db_configFile){
    $oraCFG = Import-Clixml -Path $db_configFile
    LogWrite "Oracle Home password supplied" -loginfo
    $db_details.Add('DBUA_CMD',"dbua -sid $($db_details.SID) -backupLocation $rman_path -silent -performFixUp true -oracleHomeUserPassword `"$($oraCFG.caciORAPass)`"")
  } else {
    LogWrite "No Oracle Home password" -loginfo
    $db_details.Add('DBUA_CMD',"dbua -sid $($db_details.SID) -backupLocation $rman_path -silent -performFixUp true")
  }


  # $db_details.Add('DBUA_CMD',"dbua -sid $($db_details.SID) -backupLocation $rman_path -skipListenersMigration -silent -performFixUp true")
  #-oracleHomeUserPassword $oraCFG.caciORAPass
  #dbua -sid CVPROD01 -createGRP true -createlistener LISTENER:1521 -silent -performFixUp true
  #-backupLocation C:\temp
  LogWrite "Executing DBUA Command : $($db_details.DBUA_CMD)" -loginfo
  LogWrite "In Oracle Home : $($db_details.NEW_HOME)" -loginfo
  LogWrite "Performing database upgrade of : $($db_details.SID)" -logout
  LogWrite "Service will be unavailable for the duration (avg 45 minutes elapse)" -logwarn -logout
  $env:ORACLE_HOME=$db_details.NEW_HOME
  $env:JAVA_HOME=$db_details.NEW_HOME + '\jdk'
  $env:PATH="$($db_details.NEW_HOME)\bin;$($db_details.NEW_HOME)\jdk\bin;" + $env:PATH

  LogWrite "Command: $($db_details.DBUA_CMD)" -loginfo
  $dbua_out = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $db_details.DBUA_CMD

  # Persist DBUA output for CI troubleshooting
  try {
    $artifactsDir = Join-Path $global:basedir 'artifacts'
    if (-not (Test-Path $artifactsDir)) {
      New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null
    }
    $dbuaLogPath = Join-Path $artifactsDir ("dbua_output_{0}.log" -f $db_details.SID)
    $dbua_out | Out-File -FilePath $dbuaLogPath -Encoding UTF8 -Force
  } catch {
    LogWrite "Failed to write DBUA output log: $($_.Exception.Message)" -logwarn
  }

  # Capture datapatch exit status reported by DBUA (if present)
  try {
    $datapatchExit = $null
    foreach ($line in $dbua_out) {
      if ($line -match 'datapatch\s+returned\s+with\s+exit\s+status\s+(\d+)') {
        $datapatchExit = [int]$matches[1]
      }
    }

    if ($null -ne $datapatchExit) {
      $db_details['DBUA_DATAPATCH_EXIT_STATUS'] = $datapatchExit
      LogWrite "DBUA reported datapatch exit status: $datapatchExit" -loginfo

      $statusPath = Join-Path $artifactsDir 'dbua_datapatch_status.json'
      $payload = [ordered]@{
        SID = $db_details.SID
        Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        OracleHome = $db_details.NEW_HOME
        DatapatchExitStatus = $datapatchExit
      }
      $payload | ConvertTo-Json -Depth 5 | Out-File -FilePath $statusPath -Encoding UTF8 -Force
    } else {
      LogWrite "DBUA output did not include a datapatch exit status line" -logwarn
    }
  } catch {
    LogWrite "Failed to parse/write DBUA datapatch status: $($_.Exception.Message)" -logwarn
  }

#  foreach ($dbua_push in $dbua_out) {Add-content $oracle_upgrade_log -value $dbua_push}


  if (-not ($dbua_out -match "Database move has been completed successfully, and the database is ready to use.")) {
    LogWrite "Database upgrade has failed" -logwarn -logout
    LogWrite -errid "abend" -logout;
    exit
  } else {

      LogWrite "Database upgrade Finalising" -logout
      # Migrate the password file from old to new home
      migrate_password_file $db_details

      # Ensure SPFILE exists
      check_create_spfile $db_details

    LogWrite "Database upgrade completed" -logout
    $db_details.ORACLE_HOME = $db_details.NEW_HOME
  }



  return $db_details
}

Function remove_listener
{
  Param (
    $db_details
  )
  LogWrite "Removinging Listener for 12c home" -loginfo
  LogWrite "19c listener is created during first upgrade" -loginfo
  $listener_12c = Get-WmiObject win32_service | Where-Object{$_.Name -match "OracleOraDB12Home1TNSListener"} #PathName
  if ($listener_12c){
    $discard = $listener_12c.StopService()
    $discard = $listener_12c.delete()
    LogWrite "12c Listener removed" -loginfo
  }
  $listener_19c = Get-WmiObject win32_service | Where-Object{$_.Name -match "OracleOraDB19Home1TNSListener"}
  if ($listener_19c){
    $db_details.Add('LISTENER_19c',"EXISTS")
    LogWrite "19c Listener already exists" -loginfo
  }
  return $db_details
}

Function oracle_db_upgrade
{
  Param (
    $db_details
  )
  LogWrite "Running Setup Command:" -loginfo

  $env:ORACLE_HOME=$db_details.NEW_HOME
  $env:JAVA_HOME=$db_details.NEW_HOME + '\jdk'
  $env:PATH=$env:PATH + ";$($db_details.NEW_HOME)\bin;$($db_details.NEW_HOME)\jdk\bin"


  $run_cmd = "$($db_details.NEW_HOME_SETUP_CMD) -silent -noconfig -WaitForCompletion -responseFile $($db_details.NEW_HOME_RESPONSE_FILE)"
  LogWrite "Command: $run_cmd" -loginfo
  $discard = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $run_cmd

}

function generate_enable_archivelog
{
  Param (
    $db_details
  )
LogWrite "Generating Archivelog Enable : $($db_details.UPGRADE_ENABLE_ARCHIVELOG_FILE)" -loginfo
LogWrite "Removing old file" -loginfo

$discard = Remove-Item -Path $db_details.UPGRADE_ENABLE_ARCHIVELOG_FILE -Force -ErrorAction SilentlyContinue

LogWrite "Generating file" -loginfo

Add-content $db_details.UPGRADE_ENABLE_ARCHIVELOG_FILE -value "shutdown immediate;"
Add-content $db_details.UPGRADE_ENABLE_ARCHIVELOG_FILE -value "startup mount;"
Add-content $db_details.UPGRADE_ENABLE_ARCHIVELOG_FILE -value "alter system set db_recovery_file_dest_size = 50g scope=both sid='*';"
Add-content $db_details.UPGRADE_ENABLE_ARCHIVELOG_FILE -value "alter system set db_recovery_file_dest ='$($db_details.FRA)' scope=both sid='*';"
#alter system set db_recovery_file_dest ='C:\CACI\DBTier\fast_recovery_area' scope=both sid='*';
Add-content $db_details.UPGRADE_ENABLE_ARCHIVELOG_FILE -value "alter database archivelog;"
Add-content $db_details.UPGRADE_ENABLE_ARCHIVELOG_FILE -value "alter database open;"


LogWrite "Archivelog File complete" -loginfo
return $db_details
}

function generate_disable_archivelog
{
  Param (
    $db_details
  )
LogWrite "Generating Archivelog Disable : $($db_details.UPGRADE_DISABLE_ARCHIVELOG_FILE)" -loginfo
LogWrite "Removing old file" -loginfo

$discard = Remove-Item -Path $db_details.UPGRADE_DISABLE_ARCHIVELOG_FILE -Force -ErrorAction SilentlyContinue

LogWrite "Generating file" -loginfo

Add-content $db_details.UPGRADE_DISABLE_ARCHIVELOG_FILE -value "shutdown immediate;"
Add-content $db_details.UPGRADE_DISABLE_ARCHIVELOG_FILE -value "startup mount;"
Add-content $db_details.UPGRADE_DISABLE_ARCHIVELOG_FILE -value "alter database noarchivelog;"
Add-content $db_details.UPGRADE_DISABLE_ARCHIVELOG_FILE -value "alter database open;"

LogWrite "Noarchivelog File complete" -loginfo
return $db_details
}

Function oracle_upgrade_db
{
  Param (
    $db_details
  )


   LogWrite "Starting upgrade of database : $($db_details.SID)" -logout
   $db_details.Add('DBCA_RESPONSE_FILE',"$($db_details.NEW_HOME)\CACI_DBCA_$($db_details.SID).rsp")

   $db_details = execute_upgrade $db_details
   register_db_networking $db_details

   return $db_details
}

Export-ModuleMember -Function oracle_upgrade_db

function migrate_password_file
{
   Param (
     [Parameter(Mandatory)]
     $oracle_db
    )
    $orapwd_filename="PWD$($oracle_db.SID).ora"
    $orapwd_dest="$($oracle_db.NEW_HOME)\database\$orapwd_filename"
    $orapwd_src="$($oracle_db.ORACLE_HOME)\database\$orapwd_filename"

    If (!(Test-Path $orapwd_dest)) {
        LogWrite "Migrating Password file from $orapwd_src to $orapwd_dest"
    
        $env:ORACLE_HOME=$oracle_db.NEW_HOME
        $env:JAVA_HOME=$oracle_db.NEW_HOME + '\jdk'
        $env:PATH=$env:PATH + ";$($oracle_db.NEW_HOME)\bin;$($oracle_db.NEW_HOME)\jdk\bin"
    
        $run_cmd = "orapwd file=$orapwd_dest input_file=$orapwd_src"
        LogWrite "Command: $run_cmd" -loginfo
        $discard = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $run_cmd
   } else {
        LogWrite "Destination password file exists : $orapwd_dest"
   }

}

function check_create_spfile
{
   Param (
     [Parameter(Mandatory)]
     $oracle_db
    )

    # Set ORACLE_HOME to NEW_HOME for the SQL call if New home has been set
    if ($oracle_db.ContainsKey("NEW_HOME")) {
        $oracle_db.ORACLE_HOME=$oracle_db.NEW_HOME
        LogWrite "New home set, replacing Oracle home :<= $($oracle_db.ORACLE_HOME)"
    }

    $spfile="$($oracle_db.ORACLE_HOME)\database\SPFILE$($oracle_db.SID).ora"

    if (!(Test-Path $spfile)) {
        LogWrite "Creating SPFILE for database : $spfile"
        $spfile_sql="create_spfile.sql"

        $ret_sql = oracle_sql $oracle_db $spfile_sql $resource

   } else {
        LogWrite "Destination spfile exists : $spfile"
   }
}
Export-ModuleMember -Function check_create_spfile