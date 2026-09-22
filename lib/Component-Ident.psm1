# Services identification powershell functions
#

# Read in the service_ident.xml definition file

Function compident_read
{
   Param (
     [string]$compident_xml = "$($resource)\component_ident.xml"
   )
   $compident = ( Select-Xml -Path $compident_xml -XPath / ).Node

   return $compident
}
Export-ModuleMember -Function compident_read

Function compident_list
{
  [CmdletBinding( )]
   Param (
     [xml]$compident_list
   )

if (!$compident_list) {$compident_list = compident_read}

write-host -f cyan All possible Components list
write-host -f cyan ============================
    foreach ($compidnet in $compident_list.components.component) {
        write-host -f Green -NoNewline $compidnet.type ": "
        write-host -f White $compidnet.name
    }
}

Export-ModuleMember -Function compident_list
