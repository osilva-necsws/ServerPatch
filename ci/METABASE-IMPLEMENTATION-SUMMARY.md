# Metabase Patching Implementation Summary

## Overview
Successfully added Metabase upgrade capability to the CPUTomcat GitLab CI/CD pipeline with **full multi-instance support**. The implementation follows the same orchestration pattern as Oracle and Tomcat patching (check → patch → verify → report).

## Key Features
- ✅ **Multi-Instance Support**: Automatically discovers and patches all Metabase services (e.g., metabase-prod, metabase-test)
- ✅ **Service Management**: Gracefully stops services, replaces JAR files, and restarts services
- ✅ **Java 21 Validation**: Verifies winsw.xml points to Java 21
- ✅ **ZIP/JAR Support**: Handles both JAR and ZIP files from Artifactory
- ✅ **Timestamped Backups**: Creates backups before patching (metabase.jar.backup.YYYYMMDD_HHMMSS)
- ✅ **Email Reporting**: HTML email reports with verification status for all instances
- ✅ **Error Resilience**: Individual instance failures don't stop patching of other instances

## Architecture

### 1. Discovery Phase - Check-Metabase-Installed.ps1
**Purpose**: Discover all Metabase Windows services on the target server

**Process**:
1. Searches for all Windows services matching `*metabase*` pattern
2. For each service found:
   - Extracts installation directory from service PathName (e.g., `D:\CACI\WebTier\portals\prod\metabase\winsw\winsw.exe`)
   - Locates `metabase.jar` file
   - Parses `winsw.xml` to detect Java version
3. Creates artifact with array of all instances

**Artifact Output** (`metabase_instance.json`):
```json
{
  "Hostname": "CVPROD01",
  "Timestamp": "2026-01-22 10:30:45",
  "InstanceCount": 2,
  "Instances": [
    {
      "ServiceName": "metabase-prod",
      "InstallationRoot": "D:\\CACI\\WebTier\\portals\\prod\\metabase",
      "JarPath": "D:\\CACI\\WebTier\\portals\\prod\\metabase\\metabase.jar",
      "JavaVersion": "21"
    },
    {
      "ServiceName": "metabase-test",
      "InstallationRoot": "D:\\CACI\\WebTier\\portals\\test\\metabase",
      "JarPath": "D:\\CACI\\WebTier\\portals\\test\\metabase\\metabase.jar",
      "JavaVersion": "21"
    }
  ]
}
```

### 2. Patching Phase - Patch-Metabase.ps1
**Purpose**: Download Metabase package and patch all discovered instances

**Process**:
1. Downloads JAR/ZIP from Artifactory URL (`$env:cpu_PatchMetabase`)
2. Loads instance data from `metabase_instance.json`
3. **For each instance**:
   - Stops the Metabase service
   - Creates timestamped backup of existing JAR
   - Deploys new JAR (extracts if ZIP format)
   - Starts the Metabase service
   - Waits 30 seconds for service to stabilize
   - Tracks success/failure status
4. Continues patching remaining instances even if one fails

**Artifact Output** (`metabase_patch_complete.json`):
```json
{
  "Hostname": "CVPROD01",
  "PatchDate": "2026-01-22 10:35:12",
  "MetabasePackage": "metabase-v0.50.10.jar",
  "SuccessCount": 2,
  "FailedCount": 0,
  "PatchedInstances": [
    {
      "ServiceName": "metabase-prod",
      "InstallationRoot": "D:\\CACI\\WebTier\\portals\\prod\\metabase",
      "BackupPath": "D:\\CACI\\WebTier\\portals\\prod\\metabase\\metabase.jar.backup.20260122_103512",
      "NewJarSize": 314572800
    },
    {
      "ServiceName": "metabase-test",
      "InstallationRoot": "D:\\CACI\\WebTier\\portals\\test\\metabase",
      "BackupPath": "D:\\CACI\\WebTier\\portals\\test\\metabase\\metabase.jar.backup.20260122_103545",
      "NewJarSize": 314572800
    }
  ],
  "FailedInstances": []
}
```

### 3. Verification Phase - Verify-Metabase-Patch.ps1
**Purpose**: Verify all patched instances are running correctly

**Process**:
1. Loads patch completion data
2. **For each patched instance**:
   - Checks service is running
   - Verifies JAR file exists and size matches
   - Validates winsw.xml points to Java 21
   - Tracks any issues found
3. Categorizes results: Success, Warning, or Failed
4. Creates verification artifact with detailed status

**Artifact Output** (`metabase_verification.json`):
```json
{
  "Hostname": "CVPROD01",
  "Timestamp": "2026-01-22 10:38:30",
  "MetabasePackage": "metabase-v0.50.10.jar",
  "VerificationCount": 2,
  "SuccessCount": 2,
  "WarningCount": 0,
  "FailedCount": 0,
  "OverallStatus": "SUCCESS",
  "Verifications": [
    {
      "ServiceName": "metabase-prod",
      "ServiceRunning": true,
      "JarExists": true,
      "JarSize": 314572800,
      "WinswXmlExists": true,
      "JavaVersion": "21",
      "JavaVersionCorrect": true,
      "Issues": []
    },
    {
      "ServiceName": "metabase-test",
      "ServiceRunning": true,
      "JarExists": true,
      "JarSize": 314572800,
      "WinswXmlExists": true,
      "JavaVersion": "21",
      "JavaVersionCorrect": true,
      "Issues": []
    }
  ]
}
```

### 4. Reporting Phase - Generate-Pipeline-Report.ps1
**Purpose**: Generate HTML email report with Metabase verification results

**Email Report Format**:
```
Metabase Patching: CVPROD01 - SUCCESS

Package: metabase-v0.50.10.jar
Instances: 2 (2 success)
  ✓ metabase-prod - JAR: 300.00 MB
  ✓ metabase-test - JAR: 300.00 MB
  
Timestamp: 2026-01-22 10:38:30
```

**Display Features**:
- Green checkmarks for successful instances
- Red X for failed instances
- Yellow warnings for Java version mismatches
- Individual instance details with JAR sizes
- Issue counts per instance

## GitLab CI/CD Integration

### Pipeline Variables
Added to `.gitlab-ci.yml`:
```yaml
variables:
  cpu_PatchMetabase:
    value: "https://artifactory.example.com/metabase/metabase-v0.50.10.jar"
    description: "Artifactory URL for Metabase package (JAR or ZIP)"
```

### Pipeline Jobs
1. **check_metabase_installed**: Discovers Metabase services
2. **patch_metabase**: Downloads and patches all instances
3. **verify_metabase_patch**: Verifies successful installation

### Trigger Options
Added "Patch Metabase" to ACTION dropdown in trigger_multi_server job

## Multi-Instance Handling

### Scenario Examples

**Single Instance Server**:
- Detects: `metabase-prod`
- Patches: 1 instance
- Reports: 1 instance verified

**Multi-Instance Server**:
- Detects: `metabase-prod`, `metabase-test`, `metabase-dev`
- Patches: All 3 instances sequentially
- Reports: 3 instances verified with individual statuses

**Partial Failure**:
- Detects: `metabase-prod`, `metabase-test`
- Patches: prod succeeds, test fails
- Reports: 1 success, 1 failed (with details)
- Pipeline: Overall status = FAILED

### Error Handling
- Service stop timeout: 60 seconds, then force stop
- Service start timeout: Waits 30 seconds after start
- Individual failures tracked separately
- Continues patching remaining instances
- Final status based on FailedCount

## File Structure

```
cputomcat/
├── ci/
│   ├── Check-Metabase-Installed.ps1      [NEW - Multi-instance discovery]
│   ├── Patch-Metabase.ps1                [NEW - Multi-instance patching]
│   ├── Verify-Metabase-Patch.ps1         [NEW - Multi-instance verification]
│   ├── Generate-Pipeline-Report.ps1      [UPDATED - Multi-instance reporting]
│   └── .gitlab-ci.yml                    [UPDATED - Metabase jobs added]
├── artifacts/
│   ├── metabase_instance.json            [Generated by check job]
│   ├── metabase_patch_complete.json      [Generated by patch job]
│   └── metabase_verification.json        [Generated by verify job]
```

## Usage

### Manual Trigger
1. Go to GitLab CI/CD → Pipelines
2. Click "Run pipeline"
3. Select ACTION: "Patch Metabase"
4. Set `cpu_PatchMetabase` to Artifactory URL
5. Enter target servers in `TARGET_SERVERS`
6. Click "Run pipeline"

### Example Artifactory URLs
```
# JAR file
https://artifactory.example.com/metabase/metabase-v0.50.10.jar

# ZIP file (will be extracted)
https://artifactory.example.com/metabase/metabase-v0.50.10.zip
```

## Testing Recommendations

### Test Scenarios
1. **Single Instance**: Server with one Metabase service
2. **Multiple Instances**: Server with 2+ Metabase services
3. **No Instances**: Server without Metabase (should skip gracefully)
4. **Service Name Variations**: Test with different naming patterns
5. **ZIP Format**: Test with ZIP file instead of JAR
6. **Java Version Mismatch**: Test with non-Java-21 configuration
7. **Partial Failure**: Simulate one instance failing to start

### Validation Checklist
- [ ] All Metabase services discovered
- [ ] Each service stopped gracefully
- [ ] Backups created with correct timestamps
- [ ] New JAR deployed to all instances
- [ ] All services restarted successfully
- [ ] Java 21 detected in winsw.xml
- [ ] Verification artifact created
- [ ] Email report shows all instances
- [ ] Failed instances reported separately

## Comparison with Oracle/Tomcat

### Same Patterns
✓ Check → Patch → Verify → Report workflow  
✓ JSON artifact chain between jobs  
✓ Multi-server orchestration via Trigger-Multi-Server.ps1  
✓ HTML email reporting  
✓ Manual pipeline triggers  
✓ Artifactory package downloads  

### Differences
- **Simplicity**: Metabase only requires service stop/JAR replace/service start
- **No Database**: No SQL patches or database validation
- **No Domains**: Single JAR file per instance (unlike Tomcat domains)
- **Java Check**: Only validates Java 21 in winsw.xml
- **Multi-Instance**: Native support for multiple services per server

## Technical Details

### Service Discovery Method
```powershell
Get-Service | Where-Object { $_.Name -like "*metabase*" }
```

### Installation Path Extraction
```powershell
$wmi = Get-WmiObject Win32_Service -Filter "Name='$serviceName'"
$pathName = $wmi.PathName  # e.g., "D:\...\metabase\winsw\winsw.exe"
$installRoot = Split-Path (Split-Path $pathName)
```

### Java Version Detection
```powershell
[xml]$winswConfig = Get-Content "winsw.xml"
$javaExecutable = $winswConfig.service.executable
# Match patterns: jdk-21, jdk21, java.*21
```

### ZIP Extraction Logic
```powershell
if ($downloadedFile -like "*.zip") {
    Expand-Archive -Path $downloadedFile -DestinationPath $tempExtract
    $jarFile = Get-ChildItem -Path $tempExtract -Filter "*.jar" -Recurse | Select-Object -First 1
}
```

## Success Criteria
- ✅ All Metabase services on server discovered
- ✅ Each instance patched independently
- ✅ Failures isolated (one failure doesn't stop others)
- ✅ Verification confirms service running + JAR exists + Java 21
- ✅ Email report shows per-instance status
- ✅ Artifact chain works: check → patch → verify → report
- ✅ No changes to existing Oracle/Tomcat functionality

## Known Limitations
- Requires winsw-based Metabase Windows services
- Assumes metabase.jar filename (not configurable)
- winsw.xml must be in installation root
- Service names must contain "metabase" substring
- No rollback mechanism (manual restore from backup)

## Future Enhancements (Optional)
- Pre-patch health check (URL availability)
- Post-patch smoke test (HTTP endpoint check)
- Automatic rollback on verification failure
- Configurable service start timeout
- Database backup before patch (if needed)
- Version number extraction and reporting

## Author
Auto-generated for GitLab CI/CD  
Date: January 22, 2026  
Version: 1.0 (Multi-Instance Support)
