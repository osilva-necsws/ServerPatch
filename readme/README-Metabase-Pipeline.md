# Metabase Patching via Pipeline

## Overview
This automated pipeline patches Metabase instances on Windows servers by:
1. Detecting all Metabase installations
2. Downloading the new Metabase JAR from Artifactory
3. Optionally downloading OJDBC driver
4. Stopping services
5. Deleting plugins folder
6. Replacing JAR file
7. Starting services and deploying plugins

---

## How It Works

### 1. Detection (`Check-Metabase-Installed.ps1`)
- Searches for Metabase Windows services (pattern: `metabase*`)
- Parses service configuration to find installation paths
- Detects current version if available
- Creates `artifacts/metabase_instance.json`

### 2. Patching (`Patch-Metabase.ps1`)
For each detected instance:
1. **Stop Service** - Stops Metabase Windows service (60s timeout)
2. **Backup JAR** - Creates timestamped backup of current `metabase.jar`
3. **Deploy New JAR** - Copies new JAR from download (supports ZIP or direct JAR)
4. **Delete Plugins** - Removes entire `plugins/` folder to ensure clean state
5. **Download OJDBC** (optional) - Downloads Oracle JDBC driver if URL provided
6. **Start Service** - Starts the service (120s timeout)
7. **Deploy OJDBC** - After service creates plugins folder, copies OJDBC JAR
8. **Restart Service** - Restarts to load OJDBC plugin
9. **Cleanup** - Deletes backup after successful start

### 3. Verification (`Verify-Metabase-Patch.ps1`)
- Checks service is running
- Verifies Metabase responds (if applicable)
- Reports any issues

---

## Configuration Files

### GitLab CI/CD Variables (`.gitlab-ci.yml`)

**Variables to update when changing versions:**

```yaml
cpu_PatchMetabase:
  value: "https://artifactory.cyp.caci.co.uk:8051/artifactory/softwareRepo/metabase-generic-local/oss/58/0.58.4/metabase.jar"
  description: "Artifactory URL for Metabase JAR or ZIP file (direct download link)"

cpu_PatchMetabase_OJDBC:
  value: "https://artifactory.cyp.caci.co.uk:8051/artifactory/softwareRepo/oracle-jdbc-local/ojdbc8/ojdbc8.jar"
  description: "Artifactory URL for OJDBC JAR file to deploy to Metabase plugins (optional)"
```

---

## Changing Metabase Version

### Step 1: Upload New Metabase to Artifactory
1. Download Metabase JAR from Metabase website or build
2. Upload to Artifactory at path: `softwareRepo/metabase-generic-local/oss/XX/X.XX.X/metabase.jar`
   - Example: `metabase-generic-local/oss/58/0.58.4/metabase.jar`
3. Note the full URL

### Step 2: Update GitLab CI/CD Configuration
Edit `.gitlab-ci.yml`:
```yaml
cpu_PatchMetabase:
  value: "https://artifactory.cyp.caci.co.uk:8051/artifactory/softwareRepo/metabase-generic-local/oss/59/0.59.0/metabase.jar"
```

**For OJDBC updates:**
```yaml
cpu_PatchMetabase_OJDBC:
  value: "https://artifactory.cyp.caci.co.uk:8051/artifactory/softwareRepo/oracle-jdbc-local/ojdbc11/ojdbc11.jar"
```

### Step 3: Commit and Push
```bash
git add .gitlab-ci.yml
git commit -m "Update Metabase version to 0.59.0"
git push
```

### Step 4: Run Pipeline
- Go to GitLab → CI/CD → Pipelines → Run Pipeline
- Select action: "Patch Metabase"
- Select server group tag
- Run pipeline

---

## Important: Plugin Folder Behavior

### Why Plugins Folder is Deleted
Metabase automatically extracts and updates plugins from the JAR file when it starts. By deleting the `plugins/` folder before service start, we ensure:
- Old/deprecated plugins are removed
- Only current plugins from new JAR are deployed
- No version conflicts between old and new plugins

### OJDBC Deployment
Since OJDBC is not included in standard Metabase:
1. Service starts and creates empty `plugins/` folder
2. Script waits up to 30 seconds for folder creation
3. OJDBC JAR is copied to `plugins/`
4. Service restarts to load OJDBC

---

## Files Modified During Upgrade

### Replaced:
- `metabase.jar` - Main application file

### Deleted Then Recreated:
- `plugins/*` - All plugins (recreated by Metabase on start)

### Created (Optional):
- `plugins/ojdbc8.jar` - Oracle JDBC driver (if URL provided)

### Preserved:
- `metabase.db*` - Database files (H2 or connection config)
- Configuration files
- Log files

### Backed Up:
- `metabase.jar.backup_{timestamp}` - Deleted after successful start

---

## Pipeline Jobs

### 1. `check_metabase_installed`
- Detects Metabase instances
- Creates `artifacts/metabase_instance.json`

### 2. `patch_metabase`
- Downloads Metabase JAR
- Downloads OJDBC (if configured)
- Patches all detected instances
- Creates `artifacts/metabase_patch_complete.json`

### 3. `verify_metabase_patch`
- Verifies services running
- Creates `artifacts/metabase_verification.json`

---

## Supported Package Formats

### Direct JAR
```
metabase.jar
```
Script copies directly to installation folder.

### ZIP File
```
metabase.zip
├── metabase.jar
└── versions.xml (optional)
```
Script extracts JAR and optionally deploys versions.xml.

---

## Troubleshooting

### Service Won't Start After Patch
- Backup JAR preserved at `metabase.jar.backup_{timestamp}`
- Manually restore:
  ```powershell
  Stop-Service metabase-prod
  Copy-Item "metabase.jar.backup_20260211_143000" -Destination "metabase.jar" -Force
  Start-Service metabase-prod
  ```

### OJDBC Not Loaded
- Check `plugins/` folder contains `ojdbc8.jar`
- Verify service restarted after OJDBC deployment
- Check Metabase logs for plugin loading errors

### Plugins Missing
- Normal - plugins are recreated from JAR on startup
- Wait 1-2 minutes after service start
- Check Metabase logs if plugins don't appear

---

## Environment Variables Used

- `cpu_PatchMetabase` - Metabase JAR/ZIP URL (required)
- `cpu_PatchMetabase_OJDBC` - OJDBC JAR URL (optional)

Leave `cpu_PatchMetabase_OJDBC` empty to skip OJDBC deployment.

---

## Related Scripts

- `ci/Check-Metabase-Installed.ps1` - Detection
- `ci/Patch-Metabase.ps1` - Patching logic
- `ci/Verify-Metabase-Patch.ps1` - Verification
- `docs/Metabase_Upgrade.md` - Manual upgrade documentation

---

## Notes

- Supports multiple Metabase instances on same server
- Each instance patched independently
- Plugins folder refresh ensures clean state
- OJDBC deployment is automatic if URL provided
- Works with Metabase Open Source and Enterprise editions
