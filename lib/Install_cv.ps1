param (
    [switch]$DBTier_install = $false,
    [ValidateScript({if ($_){  Test-Path $_}})]
    [string]$DBTier_Drive = "E:\",
    [switch]$DBTier_oracle = $true,
    [switch]$DBTier_postgres = $true,
    [switch]$Webtier_install = $true,
    [ValidateScript({if ($_){  Test-Path $_}})]
    [string]$WebTier_Drive = "E:\",
    [string]$cvEnvType = "prod",
    [string]$oracle_sql_file="Oracle_SQL_$cvEnvType.sql"
)

# Load required .NET assemblies. Not necessary on PS Core 7+.
Add-Type -Assembly System.IO.Compression.FileSystem

function Unzip
{
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

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
$global:log_path= Resolve-Path -Path "$basedir\logs"
$global:package= Resolve-Path -Path "$basedir\package"

# Get version details and settings
. $module_path\About.ps1


Get-Module | Remove-Module

Import-module $module_path\Logging
Import-module $module_path\oracle_tools
Import-module $module_path\oracle_select
Import-module $module_path\oracle_install_home
Import-module $module_path\oracle_upgrade_db
Import-module $module_path\caci_utils
Import-module $module_path\Folder-Ident
Import-module $module_path\Postgres_Tools

LogWrite "Running $($MyInvocation.MyCommand.Name) Software Base directory : $basedir"
LogWrite "Parameters : $args"

$ChildViewBase = Get-Content -Path "$($package.path)\ChildViewBase.json" -Raw | ConvertFrom-Json

if ($DBTier_install) {

    if ($DBTier_oracle){
        # Perform an MD5 check on any packages required
        $md5list = Import-Clixml -Path "$($package.path)\pack_oracle_dbhome.xml"
        md5_file_check $md5List $package.path
        # Setup DB object
        [hashtable]$db_details = @{}
        # Install database home
        $discard = oracle_install_new_home  -db_details:$db_details -software_pack:$md5list -new_base:$DBTier_Drive
    }
    if ($DBTier_postgres){
        $md5list = Import-Clixml -Path "$($package.path)\pack_postgres_home.xml"
        md5_file_check $md5List $package.path
        # Install a New PostgreSQL home. Excludes the C drive by default. To include, comment out below, and uncomment the following line.
        $pg_base="$DBTier_Drive\CACI\DBtier\PostgreSQL".replace('\\','\')
        $pg_home="$pg_base\$($md5List.new_home)"
        $pg_pack="$($package.path)\$($md5list.file)"

        if (test-path "$pg_home"){
            LogWrite "Postgres software already installed in : $pg_home" -logout -logwarn
        } else {
            # Unzip pack and rename to version number.
            LogWrite "Unpacking Postgres software : $pg_home" -logout -logwarn
            unzip $pg_pack $pg_base
            Rename-item -Path "$pg_base\pgsql" -NewName "$pg_home"  
            postgres_initdb -pg_home:"$pg_home"
            postgres_service_install -pg_home:"$pg_home"
            start_postgres -svc_match:$pg_service_name
        }
    }
}

if ($Webtier_install){
    $WebTierApex = $ChildViewBase.Platforms | where-object Type -eq 'WebTierApex'
    $md5Check=New-Object PsObject -property @{name = 'WebTier for Apex(CV)';file = $WebTierApex.packName; md5 = $WebTierApex.md5}

    md5_file_check $md5Check $package.path
    $webTarget = $WebTier_Drive + $webtierApex.defaultInstallPath

    if (-not (test-path($webTarget))){
        LogWrite "Upacking WebTier to $webTarget" -logout -logwarn
        unzip "$($package.path)\$($WebTierApex.packName)" $webTarget
    } else {
        LogWrite "WebTier already deployed in $WebTarget - Reconfiguring already existing deployment" -logout -logwarn
    }
    $WebTierApexEnv = $ChildViewBase.Environments | where-object Name -eq $cvEnvType
    LogWrite "Updating ORDS Credentials for Env : $($WebTierApexEnv.Name)" -logout -logwarn
    LogWrite "Database Details : $($WebTierApexEnv.OracleDB.HOST):$($WebTierApexEnv.OracleDB.PORT)/$($WebTierApexEnv.OracleDB.SID)" -logout

    $WebConfig = $webTarget + '\config'

    $oracle_sql_file = "Account_set_$($WebTierApexEnv.oracleDB.SID).sql"
    if (test-path $oracle_sql_file){remove-item $oracle_sql_file -ErrorAction SilentlyContinue}

    # Update database credentials
    ords_db_update $WebTierApexEnv $webConfig -output_orasql -sqlFilename:$oracle_sql_file
    # Install as Service

    $Tomcat_Platforms = $ChildViewBase.Platforms | where-object Type -eq "WebTierApex"
    tomcat_pool_update $WebTier_Drive $WebTierApexEnv $Tomcat_Platforms -output_orasql -sqlFilename:$oracle_sql_file -support_pool -yjb_pool 
    
    # Install Required JDK's
    $jdkPacks = $ChildViewBase.Platforms | where-object Type -like "JDK*"
    Install_jdk $WebTier_Drive $Tomcat_Platforms $jdkPacks $package
    # Register with database
}


<#
$md5list | Export-Clixml -Path "$($package.path)\pack_webtier.xml"
#$creds = @(
#    [pscustomobject]@{env="CVPROD01"; username = "APEX_PUBLIC_USER"; password="Appl3"}
#    [pscustomobject]@{env="CVPROD01"; username = "APEX_LISTENER"; password="Orang3"}
#    [pscustomobject]@{env="CVPROD01"; username = "APEX_REST_PUBLIC_USER"; password="L3mon"}
#)

$mydata = @"
{
    "version": "5.5.0",
    "name": "WebTier pack",
    "file": "WebTier.zip",
    "space": 2030563328,
    "md5": "1ABBC0E988ABB66C60EECB73222D069F",
    "oracleDB":[
        {"SID": "CVPROD01", "HOST" : "localhost", "PORT" : "1521", "creds":[
            {username:"APEX_PUBLIC_USER",password:"Appl3"},
            {username:"APEX_LISTENER",password:"Orang3"},
            {username:"APEX_REST_PUBLIC_USER",password:"L3mon"}
        ]
        },
         {"SID": "CVTEST01", "HOST" : "localhost", "PORT" : "1521", "creds":[
            {username:"APEX_PUBLIC_USER",password:"Appl3"},
            {username:"APEX_LISTENER",password:"Orang3"},
            {username:"APEX_REST_PUBLIC_USER",password:"L3mon"}
        ]
        }   
    ]
}
"@

    "ora_db": "CVPROD01",
    "ora_host": "localhost",
    "ora_port": "1521",
    "creds":[
            {env:"CVPROD01",username:"APEX_PUBLIC_USER",password:"Appl3"},
            {env:"CVPROD01",username:"APEX_LISTENER",password:"Orang3"},
            {env:"CVPROD01",username:"APEX_REST_PUBLIC_USER",password:"L3mon"}
    ]
  }
"@

$myobj | convertto-json -depth 4 | Set-Content -Path "$($package.path)\pack_webtier_new.json"

$myobj2 = Get-Content -Path "$($package.path)\pack_webtier_new.json" -Raw | ConvertFrom-Json

#>