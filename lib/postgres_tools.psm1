# Add in unzip function
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

Function stop_postgres
{
   Param (
     [string]$svc_match="*",
     [switch]$svc_remove=$false
   )
    $Postgres_services = Get-WmiObject win32_service | Where-Object{$_.state -eq 'Running' -and ($_.PathName -like '*pg_ctl*')  -and ($_.Name -like $svc_match) }
    $Postgres_services_count = ($Postgres_services | measure-object).count


    switch ( $Postgres_services_count )
    {
        0 {LogWrite "No running PostgreSQL services found" -logout}
        1 {
            LogWrite "Found PostgreSQL service for $($Postgres_services.name) .. Stopping" -logout
            $Postgres_services.StopService() | Out-Null
            LogWrite "$($Postgres_services.name) .. Stopped" -logout
            if ($svc_remove) {
                LogWrite "$($Postgres_services.name) .. Removing" -logout
                $Postgres_services.Delete() | Out-Null
            }
          }
         default
          {
            LogWrite "Unable to idenfity a single Postgres service. Multiple services installed" -logout
          }
    }
 sleep 10

}

Export-ModuleMember -Function stop_postgres

Function start_postgres
{
   Param (
     [string]$svc_match="*"
   )
    $Postgres_services = Get-WmiObject win32_service | Where-Object{$_.state -eq 'Stopped' -and ($_.PathName -like '*pg_ctl*')  -and ($_.Name -like $svc_match) }
    $Postgres_services_count = ($Postgres_services | measure-object).count


    switch ( $Postgres_services_count )
    {
        0 {LogWrite "No stopped PostgreSQL services found" -logout}
        1 {
            LogWrite "Found PostgreSQL service for $($Postgres_services.name) .. Starting" -logout
            $Postgres_services.StartService() | Out-Null
            LogWrite "$($Postgres_services.name) .. Started" -logout
          }
         default
          {
            LogWrite "Unable to idenfity a single Postgres service. Multiple services installed" -logout
          }
    }
    sleep 10
}

Export-ModuleMember -Function start_postgres

Function stop_postgres_deps
{
$service_names = @('*metabase*','*sso*') #CV host list
# $service_names = @('*impulse*','*metabase*') #Nexus host list
LogWrite "Stopping Postgres using services" -loginfo -logout
    
    foreach ($service_name in $service_names) {
        LogWrite "Checking for service matching : $service_name" -logout
    $found_service = Get-WmiObject win32_service | Where-Object{$_.Name -like $service_name }
    $found_service_count = ($found_service | measure-object).count

    switch ( $found_service_count )
        {
            0 {LogWrite "No match for $service_name" -logout}
            1 {
                LogWrite "Found service for $($found_service.displayname) [$($found_service.name)] .. Stopping" -logout
                $found_service.name | stop-service | Out-Null
                LogWrite "$($found_service.name) .. Stopped" -logout
              }
             default
              {
                LogWrite "Multiple services identified" -logout
                foreach ($found_svc in $found_service){
                    LogWrite "Stopping $($found_svc.displayname) [$($found_svc.name)]" -logout
                    $found_service.name | stop-service | Out-Null
                }
              }
        } # switch
    } # foreach
}

Export-ModuleMember -Function stop_postgres_deps

Function start_postgres_deps
{
$service_names = @('*metabase*','*cv_main*') #CV host list
# $service_names = @('*impulse*','*metabase*') #Nexus host list
LogWrite "Starting Postgres using services" -loginfo -logout
    
    foreach ($service_name in $service_names) {
        LogWrite "Checking for service matching : $service_name" -logout
    $found_service = Get-WmiObject win32_service | ?{$_.Name -like $service_name }
    $found_service_count = ($found_service | measure-object).count

    switch ( $found_service_count )
        {
            0 {LogWrite "No match for $service_name" -logout}
            1 {
                LogWrite "Found service for $($found_service.displayname) [$($found_service.name)] .. Stopping" -logout
                $found_service.name | start-service | Out-Null
                LogWrite "$($found_service.name) .. Started" -logout
              }
             default
              {
                LogWrite "Multiple services identified" -logout
                foreach ($found_svc in $found_service){
                    LogWrite "Started $($found_svc.displayname) [$($found_svc.name)]" -logout
                    $found_service.name | start-service | Out-Null
                }
              }
        } # switch
    } # foreach
}

Export-ModuleMember -Function start_postgres_deps

Function postgres_access_open
{

$pg_home=postgres_home

LogWrite "Using Postgres home : $pg_home" -logout

$pg_hba_open="$resource/pg_hba.conf"
$pg_hba="$pg_home/data/pg_hba.conf"
$pg_hba_bck="$pg_home/data/pgcpu_pg_hba.conf"

# Check files are there (verfiying resource/data paths)
if ((test-path $pg_hba_open) -and (test-path $pg_hba)) {

# Check there isnt already a backup

    if (-not (test-path $pg_hba_bck)) {
        LogWrite "No prior hba backup found" -logout
        copy-item $pg_hba $pg_hba_bck
    }
    # Remove and replace pg_hba with an open access one
    remove-item $pg_hba
    copy-item $pg_hba_open $pg_hba

    LogWrite "Using open pg_hba from :$pg_hba_open to $pg_hba" -logout
    # Recycle postgres to pull in the change
    stop_postgres

    sleep 15

    start_postgres


} else {
    LogWrite "pg_hba source or target not found" -logout
}

}
Export-ModuleMember -Function postgres_access_open

Function postgres_access_revert
{

$pg_home=postgres_home

LogWrite "Using Postgres home : $pg_home" -logout

$pg_hba_open="$resource/pg_hba.conf"
$pg_hba="$pg_home/data/pg_hba.conf"
$pg_hba_bck="$pg_home/data/pgcpu_pg_hba.conf"

# Check files are there (verfiying backup/data paths)
if ((test-path $pg_hba_bck) -and (test-path $pg_hba)) {

# Check for the backup

    if (-not (test-path $pg_hba_bck)) {
        LogWrite "No prior hba backup found, cannot revert" -logout
    } else {
        # Remove and replace pg_hba with an original access one
        LogWrite "Reverting pg_hba from :$pg_hba_bck to $pg_hba" -logout

        remove-item $pg_hba
        copy-item $pg_hba_bck $pg_hba

        # Tidy up pg_hna backup
        if ((test-path $pg_hba) -and (test-path $pg_hba_bck)) {remove-item $pg_hba_bck}

        # Recycle postgres to pull in the change
        stop_postgres

        sleep 15

        start_postgres
    }
} else {
    LogWrite "pg_hba backup or target not found" -logout
}

}
Export-ModuleMember -Function postgres_access_revert

Function postgres_dumpall
{
   Param (
#     [string]$pg_home,
     [string]$pg_user='postgres',
     [string]$pg_data,
     [string]$pg_dumpfile="cpu_dump.dmp"
   )
$pg_home=postgres_home
LogWrite "Performing database backup" -loginfo -logout
LogWrite "Using Postgres home : $pg_home" -logout

$pg_base=split-path $pg_home -Parent
$pg_backup="$pg_base\backup"
$pg_dumpfile="$pg_backup\$pg_dumpfile"


LogWrite "               base : $pg_base" -logout
LogWrite "             backup : $pg_backup" -logout
LogWrite "           dumpfile : $pg_dumpfile" -logout

if (-not (test-path $pg_backup)) {
	$discard = New-Item -Path $pg_base -Name "backup" -ItemType "directory"
} else {
# Directory exist, check for overwrite
    if (test-path $pg_dumpfile) {
        

        $archive_dumpfile="$(Get-Date -f yyyyMMdd_HH-mm)_pre_dump.dmp"
        LogWrite "Previous dumpfile found, renaming to $archive_dumpfile" -logout
	$discard = Rename-Item -Path $pg_dumpfile -NewName $archive_dumpfile
    }
}

# Open up access
postgres_access_open

$dumpall_cmd="pg_dumpall -U postgres --clean --if-exists > ""$pg_dumpfile"""
LogWrite "Running Dump : $dumpall_cmd" -logout
$env:PGHOME=$pg_home
$env:PATH="$pg_home\bin;$env:PATH"
$env:PGUSER="postgres"

LogWrite "Command: $dumpall_cmd" -loginfo
$discard = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $dumpall_cmd -ErrorVariable errortext 2>$null

#if ($discard.contains("pg_dumpall: error:") -or $discard.contains("pg_dumpall: could not connect"))
$dumpfile_chk = get-item $pg_dumpfile

if (($dumpfile_chk.length) -eq 0 -or $errortext -contains "could not connect to database"){
    LogWrite "Error during Dump : $errortext"  -logwarn -logout
    $pg_dumpfile="ERROR"
} else {
    if (test-path $pg_dumpfile) {
        LogWrite "Backup for Postgres cluster complete: Output in $pg_dumpfile" -logout
        }
}

#Revert Access file
postgres_access_revert

return $pg_dumpfile
}

Export-ModuleMember -Function postgres_dumpall

Function postgres_restore_all
{
   Param (
     [string]$pg_home=$null,
     [string]$pg_user='postgres',
     [string]$pg_dumpfile="cpu_dump.dmp"
   )
if (-not $pg_home) {$pg_home=postgres_home}
LogWrite "Restore Database copy" -logout -loginfo
LogWrite "Using Postgres home : $pg_home" -logout

$pg_base=split-path $pg_home -Parent
$pg_backup="$pg_base\backup"


LogWrite "               base : $pg_base" -logout
LogWrite "             backup : $pg_backup" -logout
LogWrite "           dumpfile : $pg_dumpfile" -logout

# Check for dumpfile
if (test-path $pg_dumpfile) {
    # Open up access
    postgres_access_open

    $restore_cmd="psql -U postgres -f ""$pg_dumpfile"" 2>&1"
    LogWrite "Running Restore : $restore_cmd" -logout
    $env:PGHOME=$pg_home
    $env:PATH="$pg_home\bin;$env:PATH"
    $env:PGUSER="postgres"

    LogWrite "Command: $restore_cmd" -loginfo
    $import_out = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $restore_cmd -ErrorAction SilentlyContinue

    $import_out | Out-File -FilePath "$log_path\postgres_import.log"

    #Revert Access file
    postgres_access_revert

    } else {
        LogWrite "Unable to locate dump file : $pg_dumpfile" -logfail -logout
        throw "Unable to find dump file, cannot continue"
    }
}

Export-ModuleMember -Function postgres_restore_all

Function postgres_home
{
   Param (
     [string]$svc_match="*"
   )

$Postgres_services = Get-WmiObject win32_service | Where-Object{($_.PathName -like '*pg_ctl*') -and ($_.Name -like $svc_match)}
if ($Postgres_services) {
    $pg_srv_home=($Postgres_Services.Pathname | select-string '("[^"]*"|\S)+' -AllMatches | % matches | % value | select-object -First 1) 
    $pg_srv_home=resolve-path -Path $pg_srv_home.Trim('"')
    $pg_srv_home=split-path $pg_srv_home -Parent
    $pg_srv_home=split-path $pg_srv_home -Parent
}
return $pg_srv_home
}

Export-ModuleMember -Function postgres_home

Function postgres_install
{
   Param (
     [string]$pg_newhome="14.8",
     [string]$pg_source_pack="postgresql-14.8-2-windows-x64-binaries.zip",
     [switch]$new_install,
     [switch]$include_c
   )
LogWrite "New Software installation" -logout -loginfo
$pg_zipfile="$package\$pg_source_pack"

if (-not (test-path $pg_zipfile)) {
    LogWrite "No software source found, file missing : $pg_zipfile" -logout -logfail
    throw "Missing software source"
}
# If a new install is requested, dont go looking for the current service
# to derive the install location. Find a CACI\DBTier root instead

if (-not $new_install) {$pg_current=postgres_home}

if ($pg_current){
    $pg_base=split-path $pg_current -Parent
} else {
    $caci_roots=find_installation_roots -folder_match:"CACI\DBTier" -include_c:$include_c

# No previous CACI\DBTier folders found, attempt to create one.
# Excludes C drive unless over-ridden with include_C switch.

    if (-not $caci_roots) {
        LogWrite "No CACI Root install found" -logout -logwarn
        $caci_roots=new_caci_dbtier -include_C:$include_c
    }
	if ($caci_roots.count -gt 1) {
		LogWrite "Multiple CACI folders found [$($caci_roots.deviceID)], using first one" -logout
		$caci_roots = ($caci_roots | Select-Object -first 1)
	}
	
    $pg_root="$($caci_roots.deviceID)\CACI\DBTier"
    $pg_base="$pg_root\PostgreSQL"
    if (-not (test-path $pg_base)) {New-Item -Path $pg_root -Name "PostgreSQL" -ItemType "directory" | out-null}
    LogWrite "New installation" -logout
}
LogWrite "Using Base $pg_base" -logout
$pg_home="$pg_base\$pg_newhome"


if (-not (test-path $pg_home)) {
    LogWrite "Using new home : $pg_home" -logout
    unzip $pg_zipfile $pg_base
    Rename-item -Path "$pg_base\pgsql" -NewName $pg_newhome   
    postgres_gen_env_bat -pg_home:$pg_home -replace:$true
} else {
    LogWrite "Home aleady in use, unable to install" -logout -logwarn
    LogWrite "Manually remove PostgreSQL to allow this installer to run" -logout -logwarn
    throw "Unable to install, destination home already exists"
}
return $pg_home
}
Export-ModuleMember -Function postgres_install

Function postgres_service_install
{
   Param (
     [Parameter(Mandatory=$true)][string]$pg_home,
     [string]$pg_data=$null,
     [string]$pg_service_name="ChildView_PostgreSQL"
   )


if (get-service -name $pg_service_name -ErrorAction SilentlyContinue){
        LogWrite "Service already exists : $pg_service_name. Unable to continue" -logout -logfail
        throw "Service already exists"
    }


if ($pg_data){$pg_data="-D ""$pg_data"""} else {$pg_data="-D ""$pg_home\data"""}



$service_cmd="pg_ctl register $pg_data -N $pg_service_name"
LogWrite "Creating Windows Service for : $pg_home" -logout
$env:PGHOME=$pg_home
$env:PATH="$pg_home\bin;$env:PATH"

LogWrite "Command: $service_cmd" -loginfo
$discard = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $service_cmd

Set-Service -Name $pg_service_name -Description "CACI PostgreSQL DB" -ErrorAction SilentlyContinue | out-null

return $pg_service_name
}
Export-ModuleMember -Function postgres_service_install

Function postgres_service_remove
{
   Param (
     [Parameter(Mandatory=$true)][string]$pg_home,
     [string]$pg_data=$null,
     [string]$pg_service_name="ChildView_PostgreSQL"
   )

if ($pg_data){$pg_data="-D ""$pg_data"""} else {$pg_data="-D ""$pg_home\data"""}
$pg_service_name="-N $pg_service_name"

$service_cmd="pg_ctl unregister $pg_service_name"
LogWrite "Removing Windows Service for : $pg_home" -logout
$env:PGHOME=$pg_home
$env:PATH="$pg_home\bin;$env:PATH"

LogWrite "Command: $service_cmd" -loginfo
$discard = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $service_cmd

}
Export-ModuleMember -Function postgres_service_remove

Function postgres_initdb
{
   Param (
     [Parameter(Mandatory=$true)][string]$pg_home,
     [string]$pg_old_home=$null,
     [string]$pg_data=$null
   )
# Old home required to source directory permissions

if ($pg_data){$pg_data="$pg_data"} else {$pg_data="$pg_home\data"}
LogWrite "Data Directory : $pg_data" -logout

if (-not (test-path $pg_data)){
    LogWrite "Creating Data Directory" -logout
    New-Item $pg_data -ItemType "directory" | out-null
    if (test-path "$pg_old_home\data") {
#   Initially there is a reason the data folder needs the correct permissions, as PostgreSQL requires certain permissions on the data folder for the initialistaion to run.
#   Turns out, cloning permissions from an already existing folder, causes an issue with those permissions stopping access to the data folder completely
#   Possibly due to some group policy/intrustion system locking up the data folder with permissions an administrator cannot access. This script used to dutifully copy those permissions
#   and break the new installation, stopping the initialise from running, so have commented out. (20240703)
#    LogWrite "Cloning permissions from $pg_old_home\data" -logout
#    $OrigACL = Get-Acl -Path "$pg_old_home\data"
#    Set-Acl -Path "$pg_data" -AclObject $OrigACL
    } else {
    LogWrite "Unable to clone permissions from $pg_old_home\data - directory does not exist" -logout
    }

    }

#if (-not (test-path $pg_data)){
#    LogWrite "No Data Directory" -logout -logwarn
#} else {
#    if (-not (test-path "$pg_data\pg_hba.conf")) {
#       Copy-Item "$resource/pg_hba.default" "$pg_data\pg_hba.conf"
#       LogWrite "Using default pg_hba" -logout -logwarn
#    }
# }

$pg_data="-D ""$pg_data"""

LogWrite "Initialising new DB" -logout
$service_cmd="initdb $pg_data -U postgres -A trust -E UTF8"

$env:PGHOME=$pg_home
$env:PATH="$pg_home\bin;$env:PATH"

LogWrite "Command: $service_cmd" -loginfo
$discard = Invoke-Command -ScriptBlock { param($path, $command ) cmd /c $path $command } -args $service_cmd

if ($pg_old_home){
    # Clone pg_hba.conf file to include any pre-configured setup. 
    if (test-path $pg_old_home\data\pg_hba.conf){
        LogWrite "Copying over HBA config" -logout
        Copy-item $pg_home\data\pg_hba.conf $pg_home\data\pginitdb_pg_hba.conf
        Copy-item $pg_old_home\data\pg_hba.conf $pg_home\data\pg_hba.conf
        } else {
        LogWrite "No old HBA config to clone into new home - Verify HBA settings" -logwarn -logout
        }

    # Clone Postgres.conf file to include any pre-configured settings. 
    if (test-path $pg_old_home\data\postgresql.conf){
        LogWrite "Copying over Postgres config" -logout
        Copy-item $pg_home\data\postgresql.conf $pg_home\data\pginitdb_postgresql.conf
        Copy-item $pg_old_home\data\postgresql.conf $pg_home\data\postgresql.conf


        } else {
        LogWrite "No old Postgres config to clone into new home - Verify Postgres settings" -logwarn -logout
        }
        # Set the listener = '*' where the commented line is.
        $pg_confFile=$pg_home + '\data\postgresql.conf'
        (get-content $pg_confFile) -replace "#listen_addresses = 'localhost'", "listen_addresses = '*'" | Set-Content $pg_confFile        
} else {
    LogWrite "No old home set to clone from" -logwarn -logout
}
}
Export-ModuleMember -Function postgres_initdb


Function postgres_sql
{
   Param (
     [Parameter(Mandatory=$true)][string]$pg_home,
     [string]$pg_old_home,
     [string]$pg_data=$null
   )
#$dburl="postgresql://exusername:expw@exhostname:5432/postgres"
$data=$pg_sql | psql -U postgres --csv | ConvertFrom-Csv

return $data
}
Export-ModuleMember -Function postgres_sql

Function postgres_gen_env_bat
{
Param (
    [Parameter(Mandatory=$true)][string]$pg_home,
    [string]$pgPath="$pg_home\bin;%PATH%",
    [string]$pgData="$pg_home\data",
    [string]$pgLocaleDir="$pg_home\share\local",
    [string]$pgUser="postgres",
    [string]$pgPort="5432",
    [string]$pgDatabase="postgres",
    [switch]$replace=$false,
    [string]$pgEnvFile="$pg_home\pg_env.bat"
    )

#Import-module C:\gitroot\deployment-dev\lib\Logging.psm1

$pgContent=@"
@ECHO OFF
REM The script sets environment variables helpful for PostgreSQL
REM Generated by Postgres_Tools Powershell $(get-date -f dd/MM/yyyy:HH:mm:ss)
@SET PATH=$pgPath
@SET PGDATA=$pgData
@SET PGDATABASE=$pgDatabase
@SET PGUSER=$pgUser
@SET PGPORT=$pgPort
@SET PGLOCALEDIR=$pgLocaleDir
"@

LogWrite "New pg_env.bat file : $pgContent" -loginfo


if (test-path $pgEnvFile) {
    if ($replace){
        LogWrite "OverWriting : $pgEnvFile" -loginfo
        set-content -Path $pgEnvFile -Value $pgContent
    } else {LogWrite "Unable to write new pg_env.bat - File already exists and replace set to false : $pgEnvFile" -logwarn -logout}    
} else {
    LogWrite "Writing : $pgEnvFile" -loginfo
    set-content -Path $pgEnvFile -Value $pgContent
}

}
Export-ModuleMember -Function postgres_gen_env_bat



        