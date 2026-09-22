# Tomcat Patching via Pipeline

## Overview

This automated pipeline patches Apache Tomcat instances on Windows servers by:
1. Detecting all Tomcat installations
2. Downloading version-specific binaries from Artifactory
3. Stopping services
4. Replacing shared binaries (bin/, lib/)
5. Removing default demo webapps
6. Restarting services
7. Verifying installation success

## Architecture

Tomcat uses a **shared Base directory** (CATALINA_HOME) with domain-specific configuration directories (CATALINA_BASE):

```
D:\CACI\WebTier\tomcat\          (Base - CATALINA_HOME)
├── bin\                          Shared executables (patched)
├── lib\                          Shared libraries (patched)
├── cv_main\                      Domain 1 (CATALINA_BASE)
│   ├── conf\                     Domain-specific config
│   ├── logs\                     Domain-specific logs
│   ├── webapps\                  Domain-specific apps
│   └── work\                     Domain-specific work
├── cv_maint\                     Domain 2
├── cv_support\                   Domain 3
└── cv_yjb\                       Domain 4
```

**Key Points:**
- All domains **share the same Tomcat version** from Base directory
- Only `bin/` and `lib/` are updated during patching
- Domain-specific configurations (`conf/`, `webapps/`, `logs/`) are preserved
- All domains must be patched together (no individual domain patching)

## Service Handling

The pipeline **preserves existing Windows services**:

- ✅ Services are **stopped** before updating
- ✅ Services are **restarted** after updating  
- ✅ Services are **NOT deleted or recreated**
- ✅ Service names match domain names (e.g., `cv_main`, not `Apache Tomcat cv_main`)

This ensures service configuration, startup type, and account settings remain unchanged.

## Security Hardening

---

## Configuration Files

### GitLab CI/CD Variables (`.gitlab-ci.yml`)

**Variables to update when changing versions:**

```yaml
cpu_PatchWebTier:
  value: "https://artifactory.cyp.caci.co.uk:8051/artifactory/softwareRepo/tomcat-generic-local/Tomcat9/apache-tomcat-9.0.112.zip"
  description: "Artifactory URL for Tomcat ZIP package (direct download link)"
```

---

## Changing Tomcat Version

### Step 1: Upload New Tomcat to Artifactory
1. Download Tomcat ZIP from Apache website (e.g., `apache-tomcat-9.0.120.zip`)
2. Upload to Artifactory at path: `softwareRepo/tomcat-generic-local/Tomcat9/apache-tomcat-9.0.120.zip`
3. Generate `pack_tomcat.xml` metadata file:
   ```powershell
   $md5List = @()
   $md5List += New-Object PsObject -property @{ 
       name = "WebTier pack"
       file = "apache-tomcat-9.0.120.zip"
       md5 = (Get-FileHash -Path "apache-tomcat-9.0.120.zip" -Algorithm MD5).Hash
   }
   $md5list | Export-Clixml -Path "pack_tomcat.xml"
   ```
4. Upload `pack_tomcat.xml` to same Artifactory location
5. Note the full URL

### Step 2: Update GitLab CI/CD Configuration
Edit `.gitlab-ci.yml`:
```yaml
cpu_PatchWebTier:
  value: "https://artifactory.cyp.caci.co.uk:8051/artifactory/softwareRepo/tomcat-generic-local/Tomcat9/apache-tomcat-9.0.120.zip"
```

### Step 3: Commit and Push
```bash
git add .gitlab-ci.yml
git commit -m "Update Tomcat version to 9.0.120"
git push
```

### Step 4: Run Pipeline
- Go to GitLab → CI/CD → Pipelines → Run Pipeline
- Select action: "Patch Tomcat"
- Select server group tag
- Run pipeline

---

## Important: Shared Base Directory Architecture

### Tomcat Structure
```
D:\CACI\WebTier\tomcat\          (Base - CATALINA_HOME)
├── bin\                          Shared executables (patched)
├── lib\                          Shared libraries (patched)
├── cv_main\                      Domain 1 (CATALINA_BASE)
│   ├── conf\                     Domain-specific config
│   ├── logs\                     Domain-specific logs
│   ├── webapps\                  Domain-specific apps
│   └── work\                     Domain-specific work
├── cv_maint\                     Domain 2
├── cv_support\                   Domain 3
└── cv_yjb\                       Domain 4
```

**Key Points:**
- All domains **share the same Tomcat version** from Base directory
- Only `bin/` and `lib/` are updated during patching
- Domain-specific configurations (`conf/`, `webapps/`, `logs/`) are preserved
- All domains must be patched together (no individual domain patching)

---

## Files Modified During Upgrade

### Replaced:
- `bin/*` - All Tomcat executable files
- `lib/*` - All Tomcat JAR libraries

### Deleted (Security Hardening):
- `webapps/docs/` - Tomcat documentation webapp
- `webapps/examples/` - Example webapps
- `webapps/host-manager/` - Host manager webapp
- `webapps/manager/` - Manager webapp
- `webapps/ROOT/index.jsp` - Default Tomcat welcome page

### Preserved:
- Domain directories (`cv_main/`, `cv_maint/`, etc.)
- Domain configurations (`{domain}/conf/`)
- Domain webapps (`{domain}/webapps/`)
- Domain logs (`{domain}/logs/`)
- Domain work directories (`{domain}/work/`)

### Backed Up:
- `tomcat_backup_{timestamp}/` - Full backup of current installation (deleted after successful patching)

---

## Service Handling

The pipeline **preserves existing Windows services**:

- ✅ Services are **stopped** before updating
- ✅ Services are **restarted** after updating  
- ✅ Services are **NOT deleted or recreated**
- ✅ Service names match domain names (e.g., `cv_main`, not `Apache Tomcat cv_main`)

This ensures service configuration, startup type, and account settings remain unchanged.

---

## Pipeline Jobs

### 1. `check_tomcat_installed` (Check Stage)
- Detects Tomcat installations
- Creates `artifacts/tomcat_instances.json`

### 2. `patch_tomcat` (Patch Stage)
- Downloads Tomcat ZIP package
- Verifies MD5 checksum from `pack_tomcat.xml`
- Checks for version match (skips if already patched)
- Stops all domain services
- Backs up current Base directory
- Replaces `bin/` and `lib/` directories
- Removes default demo webapps for security
- Restarts all services
- Creates `artifacts/tomcat_patch_complete.json`

### 3. `verify_tomcat_patch` (Post-Patch Stage)
- Verifies Tomcat version matches expected
- Checks all domain services are running
- Confirms `bin/` and `lib/` directories exist
- Creates `artifacts/tomcat_verification.json`

---

## Troubleshooting

### Service Won't Start After Patch
- Backup preserved at `tomcat_backup_{timestamp}/`
- Manually restore:
  ```powershell
  Stop-Service cv_main
  Remove-Item "D:\CACI\WebTier\tomcat\bin\*" -Force
  Remove-Item "D:\CACI\WebTier\tomcat\lib\*" -Force
  Copy-Item "D:\CACI\WebTier\tomcat_backup_20260211_143000\bin\*" -Destination "D:\CACI\WebTier\tomcat\bin\" -Force
  Copy-Item "D:\CACI\WebTier\tomcat_backup_20260211_143000\lib\*" -Destination "D:\CACI\WebTier\tomcat\lib\" -Force
  Start-Service cv_main
  ```

### Version Mismatch Error
- Check `artifacts/tomcat_patch_complete.json` for expected version
- Verify correct package URL in `.gitlab-ci.yml`
- Ensure ZIP filename matches version (e.g., `apache-tomcat-9.0.120.zip`)

### MD5 Checksum Failure
- Regenerate `pack_tomcat.xml` with correct MD5 hash
- Upload updated `pack_tomcat.xml` to Artifactory
- Rerun pipeline

### Domains Not Detected
- Check Windows services exist (pattern: `cv_*`)
- Verify services have ImagePath pointing to Base directory
- Review `artifacts/tomcat_instances.json` for detection details

---

## Environment Variables Used

- `cpu_PatchWebTier` - Tomcat ZIP package URL (required)
- `ACTION` - Pipeline action selector
- `SERVER_GROUP_TAG` - Target server group tag

---

## Related Scripts

- `ci/Check-Tomcat-Installed.ps1` - Detection
- `ci/Patch-Tomcat.ps1` - Patching logic
- `ci/Verify-Tomcat-Patch.ps1` - Verification
- `ci/Trigger-Multi-Server.ps1` - Multi-server orchestration
- `ci/Generate-Pipeline-Report.ps1` - Reporting
- `lib/tomcat_tools.psm1` - Utility functions

---

## Notes

- Supports multiple Tomcat domains on same server
- All domains share single Base directory (CATALINA_HOME)
- Patching updates shared binaries, preserving domain-specific configs
- Services are preserved (not recreated)
- Default demo webapps removed for security
- Works with Apache Tomcat 8.5, 9.0, and 10.x versions
- Validates critical directories exist
- Creates verification artifact

### Stage 6: Report
**Job**: `generate_report`
- Generates summary report of all servers
- Sends email report (if configured)

## What the Patch Does

The Tomcat patching process performs the following:

1. **Backup Current Version**
   - Renames `bin` → `bin_old`
   - Renames `lib` → `lib_old`

2. **Install New Version**
   - Extracts new `bin` and `lib` folders from package
   - Updates version documentation files

3. **Application Replacement**
   - Processes web applications in each domain

4. **Webapp Cleanup**
   - Removes default `index.jsp` welcome page
   - Removes unnecessary webapps (docs, manager, host-manager, examples)

5. **Service Management**
   - Stops services before patching
   - Restarts services after patching
   - Creates new Windows services
   - Starts services

## Artifacts

Each pipeline run produces the following artifacts:

| Artifact | Description | Expiration |
|----------|-------------|------------|
| `tomcat_instances.json` | Discovered Tomcat domains | 1 day |
| `tomcat_patch_complete.json` | Patch completion info | 7 days |
| `tomcat_verification.json` | Verification results | 7 days |
| `pipeline_report.html` | Summary report | 7 days |

## Example Artifacts

### tomcat_instances.json
```json
{
  "Hostname": "SERVER01",
  "DiscoveryDate": "2026-01-06 14:30:00",
  "TomcatDomains": [
    {
      "Name": "cv_main",
      "Home": "C:\\ChildView\\tomcat\\cv_main",
      "Base": "C:\\ChildView\\tomcat",
      "Version": "9.0.85"
    }
  ]
}
```

### tomcat_verification.json
```json
{
  "Hostname": "SERVER01",
  "VerificationDate": "2026-01-06 14:45:00",
  "ExpectedVersion": "9.0.90",
  "VerificationPassed": true,
  "DomainResults": [
    {
      "Domain": "cv_main",
      "Home": "C:\\ChildView\\tomcat\\cv_main",
      "Verified": true,
      "Version": "9.0.90",
      "ServiceRunning": true,
      "Error": null
    }
  ]
}
```

## Troubleshooting

### No Tomcat Instances Found
- Ensure the server has Tomcat installed
- Check that audit script can access Platform_config.xml
- Verify web service components exist in configuration

## Troubleshooting

### No Tomcat Instances Found

**Symptom**: Pipeline shows "No Tomcat instances found on server - skipping"

**Solution**:
- Verify Tomcat is installed in `D:\CACI\WebTier\tomcat`
- Check that `audit_get.ps1` can discover the installation

