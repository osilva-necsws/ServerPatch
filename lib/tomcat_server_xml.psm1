
function remove_ajp_listener
{
  Param (
    [Parameter(Mandatory)]
    $server_xml
)

    $remnode = $server_xml.SelectSingleNode("/Server/Service/Connector[@protocol='AJP/1.3']")
    if ($remnode -ne $null){
        LogWrite "AJP listener entry found - removing" -logout
        $remnode.ParentNode.RemoveChild($remnode)
    } else {
        LogWrite "No AJP listener entry found - skipping removal" -logout
    }

}

Export-ModuleMember -Function remove_ajp_listener

function set_TLS
{
  Param (
    [Parameter(Mandatory)]
    $server_xml
)

    $updnode = $server_xml.SelectSingleNode("/Server/Service/Connector[@SSLEnabled='true']")
    if ($updnode -ne $null){
        LogWrite "SSL listener entry found - Updating for TLSv1.2 only" -logout
        $add_att = $server_xml.CreateAttribute("sslEnabledProtocols")
        $add_att.Value = "TLSv1.2"
        $updnode.Attributes.Append($add_att)   | out-null
    } else {
        LogWrite "No SSL listener entry found - SKipping TLS restriction to TLSv1.2" -logout
    }

}

Export-ModuleMember -Function set_TLS

function set_err_resp
{
  Param (
    [Parameter(Mandatory)]
    $server_xml
)
    $checkexist= $server_xml.SelectSingleNode("/Server/Service/Engine/Host/Valve[@className='org.apache.catalina.valves.ErrorReportValve']")
    $updnode = $server_xml.SelectSingleNode("/Server/Service/Engine/Host")
    if ($checkexist -ne $null) {
            LogWrite "Error reporting Valve already exists" -logout
    } else {        
        if ($updnode -ne $null){
        
            LogWrite "Located Host - Updating with Error page supression" -logout


            $child = $server_xml.CreateElement('Valve')
            $child.SetAttribute('className','org.apache.catalina.valves.ErrorReportValve')
            $child.SetAttribute('showReport','false')
            $child.SetAttribute('showServerInfo','false')
            $updnode.AppendChild($child) | out-null
        } else {
            LogWrite "No SSL listener entry found - SKipping TLS restriction to TLSv1.2" -logout
        }
    }# valve already exists
}

Export-ModuleMember -Function set_err_resp


function webtier_serverxml_load
{
  Param (
    [Parameter(Mandatory)]
    $server_xml_detail
)

  # Check for Server XML file
  If (!(Test-Path $server_xml_detail.filename)) {
      LogWrite "No Server XML file found at : $($server_xml_detail.filename)" -logout -logwarn
	  LogWrite -errid "abend" -logout
      exit
  }


LogWrite "Loading Server XML file : $($server_xml_detail.filename)" -logout
 
#$server_xml = ( Select-Xml -Path $server_xml_detail.filename -XPath /).Node

$server_xml = New-Object System.Xml.XmlDocument 
$server_xml.PreserveWhitespace = $true
$server_xml.Load($server_xml_detail.filename)

return $server_xml
}

Export-ModuleMember -Function webtier_serverxml_load


function webtier_serverxml_backup_and_replace
{
  Param (
    [Parameter(Mandatory)]
    $server_xml_detail,
    [Parameter(Mandatory)]
    $server_xml
)


  $fileObj = get-item $server_xml_detail.filename
  $nameOnly = $fileObj.Name.Replace( $fileObj.Extension,'')
  $DateStamp = get-date -uformat "%Y-%m-%d@%H-%M-%S"
  $bck_name = "$nameOnly-$DateStamp$($fileObj.extension)"
  LogWrite "Backing up current Server.xml file to $bck_name" -logout
  rename-item "$($server_xml_detail.filename)" $bck_name
  LogWrite "Writing Server.xml file" -logout
  $server_xml.save("$($server_xml_detail.filename)") 
}

Export-ModuleMember -Function webtier_serverxml_backup_and_replace


function webtier_serverxml_init
{
  Param (
    [Parameter(Mandatory)]
    $server_xml_detail,
    [Parameter(Mandatory)]
    $domain_location
)
if ($server_xml_detail.containsKey('filename')) {
    $server_xml_detail.filename="$domain_location/conf/server.xml"
} else {

  $server_xml_detail.Add('filename',"$domain_location/conf/server.xml")
}



return $server_xml_detail
}

Export-ModuleMember -Function webtier_serverxml_init

function process_domains
{
	Param (
		$tc_doms
	)
[hashtable]$server_xml_detail = @{}
[xml]$server_xml

foreach ($domain in $tc_doms) {
	LogWrite "Performing security patching for domain : $domain" -loginfo
	$server_xml_detail = webtier_serverxml_init $server_xml_detail $tc_doms.home
	$server_xml = webtier_serverxml_load $server_xml_detail 
	remove_ajp_listener $server_xml
	set_TLS $server_xml
	webtier_serverxml_backup_and_replace $server_xml_detail $server_xml
	LogWrite "Removing Domain : $($domain.dom)" -loginfo
	}
	
}
