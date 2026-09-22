# Apache_proxy powershell script #
> The apache_proxy script installs apache and all its pre-requisites. It generates configuration files from templates substituting configurable urls. 

## Usage ##
Run from a powershell command prompt
- Run with Administrator privieges as it is required to install/uninstall services
- First run to generate the configuration file (by default this is written to (D:\CACI\WebTier\Config\ApacheAAP_cfg.xml)    
`Apache_proxy.ps1 -createConfigfileOnly`
- Update the configuration file with:
  - prxUrlTest - The external url for Test published via Azure application proxy - eg:__cv-proxy-test.caci.co.uk__
  - prxUrlProd - The external url for Prod published via Azure application proxy - eg:__cv-proxy-prod.caci.co.uk__
  - cvUrl - The internal url for the ChildView system - eg:__myserver.cyp.caci.co.uk__
- Re-run the script file to use the created parameter file.
- Verify any SSL certificates used are configured and the httpd_proxy.conf file updated.
- Startup the created service.
  - Check startup mode and adjust as necessary.

Can be re-run without issue.  

### Optional parameters ###
- to set where the configuration file is (-configFile) - Used to read and write out.  
- To choose to create the config file from defaults (-createConfigfileOnly).
  
### Example commandlines ###

> Run the script file creating a configuration file in the default location:  
```powershell
D:\cpu\deploymentdev\lib\Apache_proxy.ps1 -createConfigfileOnly
```
> Run the script file creating a configuration file in the specified location:  
```powershell
D:\cpu\deploymentdev\lib\Apache_proxy.ps1 -configFile:"d:\temp\myconfigFile" -createConfigfileOnly
```
> Run the script file actioning the installation (default configuration location):  
```powershell
D:\cpu\deploymentdev\lib\Apache_proxy.ps1
```
> Run the script file actioning the installation using the configuration file supplied:  
```powershell
D:\cpu\deploymentdev\lib\Apache_proxy.ps1 -configFile:"d:\temp\myconfigFile"
```



## Script actions ##
The script runs through the following process:
- Read the configuration file, or writes the defaults block to a configuration file.
- Checks VCC is installed, and installs if its missing
- Checks Apache has been installed as a service and removes the service if it exists.
- Unzip the Apache package
- Creates the httpd.conf file from the template, replacing the server root [srvRoot] and listen port [lsnPort] entries.
- Creates the httpd_proxy.conf file - Replacing [proxyUrl] and [cvUrl] with the supplied values.


## Configuration details ##

### Parameter excerpt from the script ###

```powershell
$installSet = @{}                                                                               
$installSet.add("cfgLoc",$configFile)                                                       # cfgloc : The configuration file name (supplied as a parameter with a default value D:\CACI\WebTier\Config\ApacheAAP_cfg.xml)
$installSet.add("vccPkg","vc_redist.x64.exe")                                               # vccPkg : The vcc redistributable pack in the packages folder
$installSet.add("vccMin","Microsoft Visual C++ 2022 X64 Minimum Runtime - 14.42.34433")     # vccMin : The registered name for the vcc version
$installSet.add("vccAdd","Microsoft Visual C++ 2022 X64 Additional Runtime - 14.42.34433")  # vccAdd : The registered name for the vvc version (additional)
$installSet.add("apaInstall","D:\CACI\WebTier\ApacheAAP")                                   # apaInstall : Installation folder for Apache
$installSet.add("apaBase","D:\CACI\WebTier\ApacheAAP\Apache24")                             # apaBase : Apache base location
$installSet.add("apaPkg","httpd-2.4.62-240904-win64-VS17.zip")                              # apaPkg : The apache source package
$installSet.add("apaCfg","AAP_httpd.conf")                                                  # apaCfg : Source template file (from resources) 
$installSet.add("apaCfgProxy","AAP_httpd_proxy.conf")                                       # apaCfgProoxy : Source template file (from resources)
$installSet.add("apaSvc","Apache24 for Azure Application Proxy")                            # apaSvc : The Apache service name
$installSet.add("prxUrlTest","cv-proxy-test.caci.co.uk")                                    # prxUrlTest : Azure App Proxy URL for Test system (ports 8*)
$installSet.add("prxUrlProd","cv-proxy-prod.caci.co.uk")                                    # prxUrl : Azure App Proxy URL for Prod system (ports 9*)
$installSet.add("cvUrl","lon-cygweb-01.cyp.caci.co.uk")                                     # cvUrl : ChildView host URL
```

### Configuration file example ###
Example configuration file written out by the script. This can be modified and used in subsequent runs.

```xml
<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
  <Obj RefId="0">
    <TN RefId="0">
      <T>System.Collections.Hashtable</T>
      <T>System.Object</T>
    </TN>
    <DCT>
      <En>
        <S N="Key">apaInstall</S>
        <S N="Value">D:\CACI\WebTier\ApacheAAP</S>
      </En>
      <En>
        <S N="Key">apaPkg</S>
        <S N="Value">httpd-2.4.62-240904-win64-VS17.zip</S>
      </En>
      <En>
        <S N="Key">cvUrl</S>
        <S N="Value">lon-cygweb-01.cyp.caci.co.uk</S>
      </En>
      <En>
        <S N="Key">apaBase</S>
        <S N="Value">D:\CACI\WebTier\ApacheAAP\Apache24</S>
      </En>
      <En>
        <S N="Key">vccMin</S>
        <S N="Value">Microsoft Visual C++ 2022 X64 Minimum Runtime - 14.42.34433</S>
      </En>
      <En>
        <S N="Key">prxUrlProd</S>
        <S N="Value">cv-proxy-prod.caci.co.uk</S>
      </En>
      <En>
        <S N="Key">apaSvc</S>
        <S N="Value">Apache24 for Azure Application Proxy</S>
      </En>
      <En>
        <S N="Key">vccAdd</S>
        <S N="Value">Microsoft Visual C++ 2022 X64 Additional Runtime - 14.42.34433</S>
      </En>
      <En>
        <S N="Key">apaCfg</S>
        <S N="Value">AAP_httpd.conf</S>
      </En>
      <En>
        <S N="Key">cfgLoc</S>
        <S N="Value">D:\CACI\WebTier\Config\ApacheAAP_cfg.xml</S>
      </En>
      <En>
        <S N="Key">vccPkg</S>
        <S N="Value">vc_redist.x64.exe</S>
      </En>
      <En>
        <S N="Key">prxUrlTest</S>
        <S N="Value">cv-proxy-test.caci.co.uk</S>
      </En>
      <En>
        <S N="Key">apaCfgProxy</S>
        <S N="Value">AAP_httpd_proxy.conf</S>
      </En>
    </DCT>
  </Obj>
</Objs>
```