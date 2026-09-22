# Services identification powershell functions
#

# Read in the service_ident.xml definition file

Function foldident_find
{
   Param (
     [Parameter(Mandatory)]
     [string]$folder_match
   )
   LogWrite "Looking for folders $folder_match" -loginfo

   $disks = Get-cimInstance win32_logicaldisk -Filter "DriveType='3'"
   
   $avail = $disks | ? { $_.DeviceID -notmatch "[abz]:"}
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

Export-ModuleMember -Function foldident_find

Function foldident_process
{
  Param (
    [xml]$component_list,
    [xml]$complete_list
  )

# Read the source entries
  $source_xml = "$($resource)\install_locations.xml"
  $sources = ( Select-Xml -Path $source_xml -XPath / ).Node

    foreach ($foldident in $component_list.components.component.folder_search.folder_match) {
      LogWrite "Checking for path match $($foldident.InnerXML)"
      #(Select-Xml -XPath "ancestor-or-self::*/tier" -xml $foldident).node.InnerXML
      [string]$folder_find = $foldident.InnerText
      $folder_loc = foldident_find  $foldident.InnerText
      if (!$folder_loc) {
        LogWrite "No folders found [$($foldident.InnerText)]" -logwarn
      } else {
        LogWrite "Folder found [$($foldident.InnerText)]"

        # Check the complete list for entry existance.

        $xpath_find="components/component/folders/folder[contains(text(),'$($foldident.InnerText)') and @folder_type='$($foldident.folder_type)']"
        LogWrite "Check output for existance : $xpath_find"
        $update_list = Select-XML -Xml $complete_list -XPath $xpath_find

        if ($update_list.count -eq 0) {
            LogWrite "Recording [$($foldident.InnerText)]"

            # Check an entry for the component isnt already in the complete-list - We need to add folders, rather than create
            # a whole element.

            $find_component = (Select-XML -Xml $foldident -XPath "ancestor::component").node
            $xpath_find="/components/component[@name='$($find_component.name)' and @type='$($find_component.type)' and @role='$($find_component.role)']"
            LogWrite "Identifying with $xpath_find"
            $update_existing = (Select-XML -Xml $complete_list -XPath $xpath_find).node

            if ((Select-XML -Xml $complete_list -XPath $xpath_find).count -gt 0){

            # Component already in complete_list
                LogWrite "Updating existing components folders"
                $new_entry = $update_existing
                foldident_folders


            } else {

            # Add new entry and folders
                # New XML section required
                LogWrite "Creating a new component for folders"

                $xpath_find_source='//components/component[@type=''' + $($find_component.type)+ ''']'
                $new_comp = $sources.SelectSingleNode($xpath_find_source)
                $base_comp = (select-xml -xml $foldident -xpath "ancestor::component").node
                $new_entry = $complete_list.ImportNode($new_comp,$true)
                foldident_new
                $complete_list.components.appendchild($new_entry) | Out-Null
            }

        } else {
            LogWrite "Folder already recorded [$($foldident.InnerText)]"
        } # Folder already recorded

      } # Folder found

    } # Folder iteration
    return $complete_list
} #Function

Export-ModuleMember -Function foldident_process

function foldident_new
{


# Set standard service information

  $new_entry.SetAttribute("name", $base_comp.name)
  $new_entry.SetAttribute("role", $base_comp.role)

  LogWrite "Adding new entry for $($base_comp.name) $($base_comp.role)"

  foldident_folders
#  $new_entry.folders.Insertafter($add_folders)
#    write-host -f yellow 'In main' $add_folders.gettype()
#  $new_entry.components.componenet.folders.AppendChild($add_folders)
}


function foldident_folders
{

  foreach ($folder_found in $folder_loc)
    {
    # Add a folders record
      $full_folder=$folder_found.DeviceID + "\" + $foldident.InnerText
      $new_fold = $complete_list.CreateElement("folder")
      $text_fold = $complete_list.CreateTextNode($full_folder)
      $new_fold.AppendChild($text_fold) | Out-Null
    # Creation of attribute to denote folder type
      $add_att = $complete_list.CreateAttribute("type")
      $add_att.Value = $foldident.folder_type
      $new_fold.Attributes.Append($add_att) | Out-Null
      $add_att = $complete_list.CreateAttribute("freespace")
      $add_att.Value = $folder_found.freespace
      $new_fold.Attributes.Append($add_att) | Out-Null
      $add_folders = $complete_list.ImportNode($new_fold,$true)

      $new_entry.folders.appendchild($add_folders) | Out-Null
#      $add_comp.Folders.AppendChild($add_folders) | Out-Null
    }
}
