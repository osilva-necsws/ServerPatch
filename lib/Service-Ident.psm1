# Services identification powershell functions
#

# Read in the service_ident.xml definition file

Function srvident_find
{
   Param (
     [Parameter(Mandatory)]
     [string]$srv_match
   )
   LogWrite "Looking for service $srv_match" -loginfo
   # $service_found = Get-WmiObject win32_service | ?{$_.Name -match $srv_match}
	$service_found = Get-ciminstance win32_service -Filter "name = '$($srv_match)'"
    return $service_found
}

Export-ModuleMember -Function srvident_find

Function srvident_process
{
  Param (
    [xml]$component_list,
    [xml]$complete_list
  )

  # Read the source entries
  $source_xml = "$($resource)\install_locations.xml"
  $sources = ( Select-Xml -Path $source_xml -XPath / ).Node

  # Process XML entries with a Service search record
  foreach ($compident in $component_list.components.component.srv_search.srv_match) {
    LogWrite "Checking for service $compident"
   # (Select-Xml -XPath "ancestor-or-self::*/tier" -xml $compident).node.InnerXML
    [string]$service_find = $compident
    $service_loc = srvident_find  $compident
    if (!$service_loc) {
      LogWrite "No Service found ($service_find)" -logwarn
    } else {
      LogWrite "Service found ($service_find)"

      # Check the complete list for entry existance.

      $xpath_find="descendant-or-self::components/component[@name='$compident']"
      LogWrite "XPATH FIND : $($xpath_find)"
#      (Select-Xml -XPath $xpath_find -xml $complete_list).node.InnerXML
      $update_list = $complete_list.SelectSingleNode($xpath_find)

      #"//components/component[descendant::srv_match[text()='Dhcp']]"

      # Get the parent component entry type for generating the complete list.
      $xpath_entry_type="//components/component[descendant::srv_match[text()='$compident']]"
      $entry_node = $component_list.SelectSingleNode($xpath_entry_type)
     # $entry_node = $complete_list.SelectSingleNode($xpath_entry_type)

      LogWrite "Entry type : $($entry_node.type)"

      LogWrite "Update List : $update_list $($update_list.Count)"
      if ($update_list.Count -eq 0) {
        LogWrite "Service not found in list, adding for content type [$($entry_node.type)]"

        # New XML section required
        $xpath_find_source='//components/component[@type=''' + $($entry_node.type)+ ''']'
        #$new_comp = $sources.SelectSingleNode($xpath_find_source)
        $new_comp = (Select-XML -Xml $sources -Xpath $xpath_find_source).Node

        if (!$new_comp) {LogWrite "No XML Record for  $($entry_node.type)" -logfail}
        else {

            $add_comp = $complete_list.ImportNode($new_comp,$true)
            srvident_add $add_comp $service_loc
#            LogWrite "Adding : $($add_comp.innertext)" -logout
 #           $new_entry = $complete_list.ImportNode($new_comp,$true)
            $complete_list.components.AppendChild($add_comp) | Out-Null
        }
      } else {
        LogWrite "Service already in list, skipping"
      }
    }
  }
    return $complete_list
}

Export-ModuleMember -Function srvident_process


function srvident_add
{
# Set standard service information

  $add_comp.SetAttribute("name", $entry_node.name)
  $add_comp.SetAttribute("role", $entry_node.role)
  $add_comp.SetAttribute("image_prefix", $entry_node.image_prefix)  
  $add_comp.service.name=$service_loc.Name.Tostring()
  $add_comp.service.startmode=$service_loc.StartMode.Tostring()
  $add_comp.service.exec=$service_loc.PathName.ToString()
# Add a folders record
  $new_fold = $complete_list.CreateElement("folder")
  $service_path=(split-path -path $service_loc.PathName).ToString()
  if ($service_path.startswith('"')) {$service_path = $Service_path.replace('"','')} # If the Service path has speech marks, it messes up split-path. Remove speech marks from string.
  $text_fold = $complete_list.CreateTextNode($service_path)
  $new_fold.AppendChild($text_fold) | Out-Null
# Creation of attribute to denote folder type
  $add_att = $complete_list.CreateAttribute("type")
  $add_att.Value = "service home"
  $new_fold.Attributes.Append($add_att) | Out-Null
  $add_folder = $complete_list.ImportNode($new_fold,$true)
  $add_comp.Folders.AppendChild($add_folder) | Out-Null

  if ($entry_node.type -eq 'db service'){
    # Add DB Home folders record
      $new_fold = $complete_list.CreateElement("folder")
      $oracle_bin=(split-path -path $service_loc.PathName).ToString()
      if ($oracle_bin.startswith('"')) {$oracle_bin = $oracle_bin.replace('"','')} # If the Service path has speech marks, it messes up split-path. Remove speech marks from string.
     
     # $oracle_bin = (split-path -path $service_loc.PathName).ToString()
      $oracle_home = $oracle_bin.replace('\bin','')
      $text_fold = $complete_list.CreateTextNode($oracle_home)
      $new_fold.AppendChild($text_fold) | Out-Null
      $add_att = $complete_list.CreateAttribute("type")
      $add_att.Value = "ORACLE_HOME"
      $new_fold.Attributes.Append($add_att) | Out-Null
      $oracle_space = (get-volume -filepath $oracle_home).SizeRemaining
      $add_att = $complete_list.CreateAttribute("freespace")
      $add_att.Value = $oracle_space
      $new_fold.Attributes.Append($add_att) | Out-Null
      $add_folder = $complete_list.ImportNode($new_fold,$true)
      $add_comp.Folders.AppendChild($add_folder) | Out-Null
 }


# $add_fold= $new_comp.ImportNode($new_fold,$true)
#  $new_comp.AppendChild($add_fold)

}
