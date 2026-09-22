# Metabase Upgrade Process – Documentation

## Purpose
This process upgrades:
- **Metabase JDK** (Amazon Corretto used by Metabase service)
- **Metabase application JAR** (ZIP file  containing the JAR)

It ensures:
- Service is stopped before upgrade.
- Old JDK is backed up for rollback.
- New JDK and Metabase files are deployed.
- Service is restarted and verified.
- Rollback occurs if restart fails.

---

## Prerequisites
1. **Backup** the server or have a rollback plan.
2. Ensure:
   - `metabase.zip(constains the metabase jar file)` and JDK ZIP (e.g., `jdk21.0.8_9.zip`) are in the `package` folder.
   - XML file (`pack_metabase.xml`-) contains correct entries:
     ```xml
     <S N="file">metabase.zip</S>
     <S N="name">Metabase JAR</S>
     ```
   - XML file (The NAME should not be changed(used by Upgrade_Metabase function), only the file that can be updated with the name of the zip folder inside the package folder)
   - When addidng a new version of JDK or metabase, md5 value inside (`pack_metabase.xml`) should be changed and also the FILE description. 
3. Run the batch script from **PowerShell-enabled environment**.

---

## Batch Script (`Patch_Metabase.bat`)
- Displays warning and asks for confirmation.
- Calls PowerShell module `caci_utils.psm1` which contains `Upgrade_Metabase`.

---

## PowerShell Script (`metabase_upgrade.ps1`)
- Displays warning and asks for confirmation.
- Determine BAse directories and set Global Paths
- Calls PowerShell module `Logging.psm1`
- Calls PowerShell module `caci_utils.psm1` which contains `Upgrade_Metabase`.
- Loads the XML file containing expected package details (JDK and Metabase JAR) and runs an MD5 checksum validation to ensure file integrity.

---

## PowerShell Module (`caci_utils.psm1`)
### Key Functions
- `find_installation_roots`: Locates installation directories.
- `Upgrade_Metabase`: Performs the upgrade.

---

## Upgrade_Metabase Function – Steps
1. **Read XML (pack_metabase.xml)**:
   - Extract file names for JDK and Metabase.
   - We can use the following in the function if XML parsing fails(We manually insert the names of the zip files):
   ```xml
    #if (-not $metabase_file -or $metabase_file -eq "") { $metabase_file = "metabase.zip" }
    #if (-not $jdk_zip_file -or $jdk_zip_file -eq "") { $jdk_zip_file = "jdk21.0.8_9.zip" }
     ```
   
2. **Validate Files**:
   - Check existence of JDK ZIP and Metabase ZIP.

3. **Locate Installation Root**:
   - Typically `CACI\WebTier\Java\metabase`.

4. **Stop Metabase Service**:
   - Uses CIM:
     ```powershell
     $service | Invoke-CimMethod -Name StopService
     ```

5. **Backup Old JDK**:
   - Rename `jdk` folder to `jdk_old`.

6. **Deploy New JDK**:
   - Extract ZIP:
     ```powershell
     Expand-Archive -Path $jdk_zip -DestinationPath $jdk_target -Force
     ```

7. **Deploy Metabase**:
   - If ZIP:
     - Extract to temp folder.
     - Copy `metabase.jar` to target.

8. **Restart Service**:
   - Uses CIM:
     ```powershell
     $service | Invoke-CimMethod -Name StartService
     ```

9. **Verify Service**:
   - If not running:
     - Rollback JDK.
     - Restart service.

10. **Cleanup**:
    - Remove old JDK backup if upgrade successful.

---

## Error Handling
- If files missing → abort.
- If service fails to restart → rollback JDK.
- If Metabase JAR missing in ZIP → abort.

---

## Rollback Logic
- If upgrade fails:
  - Remove new JDK.
  - Restore `jdk_old`.
  - Restart service.

---

## Logs
- All actions logged via `LogWrite` function:
  - Stop/start service.
  - File operations.
  - Success/failure messages.

---

## Key Improvements in Final Version
- Handles both ZIP for Metabase.
- Uses CIM for reliable service control.
- Fallback logic for missing XML entries.
- Cleans up temp extraction folder.
- Maintains rollback safety.
- For the first testing phase I had to force the correct file name becase the variable declared inside pack_metabase.xml was empty, invalid or not being passed, meaning that the caci_utils function Upgrade_Metabase has been also been written to look for the metabase.zip file if it fails to find the name from xml if needed. 

```

if (-not $metabase_file -or $metabase_file -eq "") {
    $metabase_file = "metabase.zip"
}
$metabase_path = Join-Path $package $metabase_file

```
---

## Full PowerShell Function Code

```powershell
function Upgrade_Metabase {
    Param (
        $software_pack
    )

    # Extract file names from XML
    $metabase_file = ($software_pack | Where-Object { $_.name -eq "Metabase JAR" }).file
    $jdk_zip_file  = ($software_pack | Where-Object { $_.name -eq "Metabase JDK" }).file
	
    #Fallback if XML parsing fails
    #if (-not $metabase_file -or $metabase_file -eq "") { $metabase_file = "metabase.zip" }
    #if (-not $jdk_zip_file -or $jdk_zip_file -eq "") { $jdk_zip_file = "jdk21.0.8_9.zip" }

    $metabase_path = Join-Path $package $metabase_file
    $jdk_zip       = Join-Path $package $jdk_zip_file

    # Validate files
    if (-not (Test-Path $metabase_path)) { LogWrite "Missing Metabase file: $metabase_path" -logfail -logout; exit }
    if (-not (Test-Path $jdk_zip)) { LogWrite "Missing JDK ZIP: $jdk_zip" -logfail -logout; exit }

    # Locate installation root
    $install_path = "CACI\WebTier\Java\metabase"
    $install_roots = find_installation_roots $install_path -include_c
    if ($install_roots.count -eq 0) { LogWrite "Metabase root not found. Exiting." -logfail -logout; exit }

    # Build paths
    $metabase_root = Join-Path $install_roots.DeviceID $install_path
    $jdk_target    = Join-Path $metabase_root "jdk"
    $metabase_jar_target = Join-Path (Join-Path $install_roots.DeviceID "CACI\WebTier\portals\prod\metabase") "metabase.jar"
    $serviceName = "metabase-prod"

    LogWrite "Checks passed. Proceeding with upgrade..." -logout

    # Stop service using CIM
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'"
    if ($service -and $service.State -eq 'Running') {
        LogWrite "Stopping service '$serviceName'" -loginfo -logout
        $service | Invoke-CimMethod -Name StopService | Out-Null
        Start-Sleep -Seconds 10
    }

    # Backup old JDK
    $jdk_backup = "${jdk_target}_old"
    if (Test-Path $jdk_backup) { Remove-Item $jdk_backup -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $jdk_target) {
        try { Rename-Item $jdk_target $jdk_backup -ErrorAction Stop }
        catch {
            LogWrite "JDK in use. Aborting upgrade." -logfail -logout
            $service | Invoke-CimMethod -Name StartService | Out-Null
            exit
        }
    }

    # Ensure folder exists
    if (-not (Test-Path $jdk_target)) { New-Item -ItemType Directory -Path $jdk_target | Out-Null }

    # Unpack JDK
    LogWrite "Unpacking JDK from $jdk_zip..." -loginfo
    Expand-Archive -Path $jdk_zip -DestinationPath $jdk_target -Force

    # Deploy Metabase JAR
    LogWrite "Deploying Metabase from $metabase_path..." -loginfo
    if ($metabase_path.ToLower().EndsWith(".zip")) {
        $tempExtractPath = Join-Path $env:TEMP "metabase_extract"
        if (Test-Path $tempExtractPath) { Remove-Item $tempExtractPath -Recurse -Force }
        Expand-Archive -Path $metabase_path -DestinationPath $tempExtractPath -Force

        $extractedJar = Join-Path $tempExtractPath "metabase.jar"
        if (-not (Test-Path $extractedJar)) {
            LogWrite "Metabase JAR not found in ZIP. Aborting." -logfail -logout
            exit
        }
        Copy-Item -Path $extractedJar -Destination $metabase_jar_target -Force
        Remove-Item $tempExtractPath -Recurse -Force
    } else {
        Copy-Item -Path $metabase_path -Destination $metabase_jar_target -Force
    }

    # Restart service using CIM
    LogWrite "Restarting service '$serviceName'" -loginfo -logout
    $service | Invoke-CimMethod -Name StartService | Out-Null
    Start-Sleep -Seconds 10

    # Verify service status
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'"
    if ($service.State -ne 'Running') {
        LogWrite "Service failed to start. Rolling back..." -logwarn -logout
        if (Test-Path $jdk_target) { Remove-Item $jdk_target -Recurse -Force }
        if (Test-Path $jdk_backup) { Rename-Item $jdk_backup $jdk_target }
        $service | Invoke-CimMethod -Name StartService | Out-Null
        LogWrite "Rollback complete." -loginfo
    } else {
        LogWrite "Metabase upgrade completed successfully." -loginfo
    }

    # Cleanup backup
    if (Test-Path $jdk_backup) { Remove-Item $jdk_backup -Recurse -Force -ErrorAction SilentlyContinue }
}
Export-ModuleMember -Function Upgrade_Metabase