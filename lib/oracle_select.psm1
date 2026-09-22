function db_choice {
    LogWrite "Enter a database:" -logout -logwarn
    foreach ($databases in $oracle_dbs) {
        LogWrite "`t$($databases.name)" -logout
    }

    do {
    $database_id = Read-Host "Please enter the database name (ctrl/c to exit):"
    } while (! $oracle_dbs.name.Contains($database_id))
    LogWrite "Database : $database_id chosen"
    return $database_id
}

function choose_db {
  Param (
    [Parameter(Mandatory)]
    [hashtable]$db_details,
    [Parameter(Mandatory=$false)]
    [string]$database_id
  )

  $null = .{

  $config_xml="$basedir\Platform_config.xml"
  # Check for Audit XML file - Removed check from cpu63 so an audit is always performed.
    & "$module_path\audit_get.ps1"
    LogWrite "Audit done" -logout
    If (!(Test-Path $config_xml)) {
        LogWrite -errid "abend" -logout
        exit
    }



  LogWrite "Loading Audit file" -logout

  [xml]$platform_config = ( Select-Xml -Path $config_xml -XPath /).Node

  $oracle_dbs = ( Select-Xml -xml $platform_config -XPath "//components/component[@type='db service']").Node

  if ($oracle_dbs.HasChildNodes) {
      if ($database_id) {
          LogWrite "Database name $database_id"
      } else {
          LogWrite "No database name supplied" -logwarn
          $database_id=db_choice
      }
      
      # Debug: List all available databases
      LogWrite "Available databases in Platform_config.xml:" -logout
      foreach ($db in $oracle_dbs) {
          LogWrite "  - Name: '$($db.name)', Type: '$($db.type)'" -logout
      }
      
      $select_db=( Select-Xml -xml $platform_config -XPath "//components/component[@name='$($database_id)']")
      if ($select_db) {
          $db_details.Add('SID',$select_DB.node.name) | Out-Null
          $db_details.Add('IMAGE_PREFIX',$select_DB.node.image_prefix) | Out-Null
          $db_details.Add('ORACLE_HOME',$select_DB.Node.SelectSingleNode("folders/folder[@type='ORACLE_HOME']/text()").value) | Out-Null
          $db_details.Add('ORACLE_HOME_FREESPACE',$select_DB.Node.SelectNodes("folders/folder[@type='ORACLE_HOME']").freespace) | Out-Null
          $base_str=$db_details.ORACLE_HOME -split "\\product"
          $base_fold=$base_str[0]
          $db_details.Add('ORACLE_BASE',$base_fold) | Out-Null
          $db_details.Add('DATAFILES',$select_DB.Node.SelectSingleNode("folders/folder[@type='DB_DATAFILES']/text()").value) | Out-Null
          $db_details.Add('DATAFILES_FREESPACE',$select_DB.Node.SelectNodes("folders/folder[@type='DB_DATAFILES']").freespace) | Out-Null
          $db_details.Add('FRA',$select_DB.Node.SelectSingleNode("folders/folder[@type='DB_FRA']/text()").value) | Out-Null
          $db_details.Add('FRA_FREESPACE',$select_DB.Node.SelectNodes("folders/folder[@type='DB_FRA']").freespace) | Out-Null
      } else {
          LogWrite "Database $database_id Not found" -logwarn
          LogWrite "Supplied Database parameter cannot be found" -logout -logwarn
          exit
      }

  } else {
      LogWrite "No databases discovered on this host" -logout -logwarn
      LogWrite "Verify this host contains a ChildView database" -logout -logwarn
      exit
  }
} # Null output pipe
  return $db_details
}
Export-ModuleMember -Function choose_db
