# PostgreSQL Patching via Pipeline

## Overview
This automated pipeline patches PostgreSQL instances on Windows servers by:
1. Detecting all PostgreSQL installations
2. Downloading version-specific binary packages from Artifactory
3. Optionally downloading orafce extension
4. Stopping services
5. Replacing binaries
6. Deploying orafce extension files
7. Starting services
8. Verifying version and extensions

---

## How It Works

### 1. Detection (`Check-PostgreSQL-Installed.ps1`)
- Searches for PostgreSQL Windows services (pattern: `postgresql*`)
- Parses service configuration to find installation paths
- Detects current version from `postgres.exe`
- Creates `artifacts/postgres_instance.json`

### 2. Patching (`Patch-PostgreSQL.ps1`)

#### Multi-Version Support
The script supports patching multiple PostgreSQL major versions in a single pipeline run:
- Downloads all configured version packages (v14, v15, etc.)
- Matches each instance to the correct package by major version
- Skips instances if their major version package is not configured

**Example:** If server has both PostgreSQL 14.15 and 15.10 instances:
- Downloads both v14 and v15 packages
- Patches v14 instance with v14 package (14.20)
- Patches v15 instance with v15 package (15.15)

#### Patching Process
For each detected instance:
1. **Stop Service** - Stops PostgreSQL service (60s timeout)
2. **Backup Binaries** - Creates timestamped backup of `bin/` and `lib/` folders
3. **Deploy New Binaries** - Copies new binaries from downloaded package
4. **Deploy Orafce Extension** (optional)
   - Copies version-specific DLL from `lib/14/` or `lib/15/` to `lib/`
   - Copies extension files (*.sql, *.control) to `share/extension/`
5. **Start Service** - Starts service (180s timeout)
6. **Cleanup** - Deletes backup after successful start

### 3. Verification (`Verify-PostgreSQL-Patch.ps1`)
- Checks service is running
- Validates version matches expected target
- Reports any issues

---

## Configuration Files

### GitLab CI/CD Variables (`.gitlab-ci.yml`)

**Variables to update when changing versions:**

```yaml
cpu_PatchPostgreSQL:
  value: "https://artifactory.cyp.caci.co.uk:8051/artifactory/softwareRepo/postgresql-generic-local/14/14.20/postgresql-14.20.zip"
  description: "Artifactory URL for PostgreSQL v14 binaries (ZIP file)"

cpu_PatchPostgreSQL_v15:
  value: "https://artifactory.cyp.caci.co.uk:8051/artifactory/softwareRepo/postgresql-generic-local/15/15.15/postgresql-15.15.zip"
  description: "Artifactory URL for PostgreSQL v15 binaries (ZIP file)"

cpu_PatchPostgreSQL_Orafce:
  value: "https://artifactory.cyp.caci.co.uk:8051/artifactory/softwareRepo/postgresql-generic-local/extensions/orafce/4.0.1/orafce.zip"
  description: "Artifactory URL for orafce extension package (optional)"
```

---

## Changing PostgreSQL Version

### Step 1: Upload New PostgreSQL Binaries to Artifactory
1. Download PostgreSQL ZIP binaries from EDB or compile
2. Upload to Artifactory at path: `softwareRepo/postgresql-generic-local/XX/XX.XX/postgresql-XX.XX.zip`
   - Example v14: `postgresql-generic-local/14/14.21/postgresql-14.21.zip`
   - Example v15: `postgresql-generic-local/15/15.16/postgresql-15.16.zip`
3. Note the full URL

### Step 2: Update GitLab CI/CD Configuration
Edit `.gitlab-ci.yml`:

**For PostgreSQL v14 updates:**
```yaml
cpu_PatchPostgreSQL:
  value: "https://artifactory.cyp.caci.co.uk:8051/artifactory/softwareRepo/postgresql-generic-local/14/14.21/postgresql-14.21.zip"
```

**For PostgreSQL v15 updates:**
```yaml
cpu_PatchPostgreSQL_v15:
  value: "https://artifactory.cyp.caci.co.uk:8051/artifactory/softwareRepo/postgresql-generic-local/15/15.16/postgresql-15.16.zip"
```

**For orafce extension updates:**
```yaml
cpu_PatchPostgreSQL_Orafce:
  value: "https://artifactory.cyp.caci.co.uk:8051/artifactory/softwareRepo/postgresql-generic-local/extensions/orafce/4.1.0/orafce.zip"
```

### Step 3: Commit and Push
```bash
git add .gitlab-ci.yml
git commit -m "Update PostgreSQL v14 to 14.21 and v15 to 15.16"
git push
```

### Step 4: Run Pipeline
- Go to GitLab → CI/CD → Pipelines → Run Pipeline
- Select action: "Patch PostgreSQL"
- Select server group tag
- Run pipeline

---

## Important: Orafce Extension

### What is Orafce?
Orafce provides Oracle compatibility functions for PostgreSQL, including:
- Oracle-style date/time functions
- String manipulation functions
- Data type conversions
- Package emulation (DBMS_OUTPUT, DBMS_RANDOM, etc.)

### Why Deploy During Patching?
PostgreSQL binary replacement removes extension DLLs. Orafce must be redeployed to maintain Oracle compatibility.

### Orafce Package Structure
```
orafce.zip
├── lib/
│   ├── 14/
│   │   └── orafce.dll    (for PostgreSQL 14.x)
│   └── 15/
│       └── orafce.dll    (for PostgreSQL 15.x)
└── extension/
    ├── orafce--3.0.sql
    ├── orafce--3.0--4.0.sql
    ├── orafce--4.0.sql
    ├── orafce--4.0--4.0.1.sql
    ├── orafce.control
    └── ...
```

### Deployment Logic
1. Script detects instance major version (14 or 15)
2. Copies correct DLL: `lib/14/orafce.dll` → `{pgRoot}/lib/orafce.dll`
3. Copies all extension files: `extension/*` → `{pgRoot}/share/extension/`

---

## Adding Support for New PostgreSQL Major Version

### Example: Adding PostgreSQL v16

**Step 1:** Add new variable to `.gitlab-ci.yml`
```yaml
cpu_PatchPostgreSQL_v16:
  value: "https://artifactory.cyp.caci.co.uk:8051/artifactory/softwareRepo/postgresql-generic-local/16/16.5/postgresql-16.5.zip"
  description: "Artifactory URL for PostgreSQL v16 binaries (ZIP file)"
```

**Step 2:** Update `Patch-PostgreSQL.ps1` download section
```powershell
# Download v16 package
if ($env:cpu_PatchPostgreSQL_v16) {
    Write-Host "Downloading PostgreSQL v16 package..."
    $v16Url = $env:cpu_PatchPostgreSQL_v16
    $v16Package = "C:\Temp\postgresql-v16.zip"
    Invoke-WebRequest -Uri $v16Url -OutFile $v16Package
    $packages["16"] = $v16Package
}
```

**Step 3:** Update orafce package
Add `lib/16/orafce.dll` to orafce.zip for PostgreSQL 16 support.

---

## Files Modified During Upgrade

### Replaced:
- `bin/*` - All PostgreSQL executable files (postgres.exe, psql.exe, etc.)
- `lib/*` - All library files (DLLs)

### Created (if orafce enabled):
- `lib/orafce.dll` - Orafce extension library
- `share/extension/orafce*.sql` - Orafce SQL scripts
- `share/extension/orafce.control` - Extension metadata

### Preserved:
- `data/*` - Database data files
- Configuration files (postgresql.conf, pg_hba.conf, etc.)
- Tablespaces
- Log files

### Backed Up:
- `bin.backup_{timestamp}/` - Deleted after successful start
- `lib.backup_{timestamp}/` - Deleted after successful start

---

## Pipeline Jobs

### 1. `check_postgresql_installed`
- Detects PostgreSQL instances
- Creates `artifacts/postgres_instance.json`

### 2. `patch_postgresql`
- Downloads all configured version packages
- Downloads orafce (if configured)
- Patches all detected instances with matching version
- Creates `artifacts/postgresql_patch_complete.json`

### 3. `verify_postgresql_patch`
- Verifies services running
- Validates versions match targets
- Creates `artifacts/postgresql_verification.json`

---

## Package Structure

### PostgreSQL Binary Package (ZIP)
```
postgresql-14.20.zip
├── bin/
│   ├── postgres.exe
│   ├── psql.exe
│   └── ...
├── lib/
│   ├── libpq.dll
│   └── ...
└── versions.xml (optional)
```

### Orafce Extension Package (ZIP)
```
orafce.zip
├── lib/
│   ├── 14/
│   │   └── orafce.dll
│   └── 15/
│       └── orafce.dll
└── extension/
    ├── orafce--4.0.sql
    ├── orafce.control
    └── ...
```

---

## Troubleshooting

### Service Won't Start After Patch
- Backup binaries preserved at `bin.backup_{timestamp}` and `lib.backup_{timestamp}`
- Manually restore:
  ```powershell
  Stop-Service postgresql-x64-14
  Remove-Item "C:\PostgreSQL\14\bin\*" -Force
  Remove-Item "C:\PostgreSQL\14\lib\*" -Force
  Copy-Item "C:\PostgreSQL\14\bin.backup_20260211_143000\*" -Destination "C:\PostgreSQL\14\bin\" -Force
  Copy-Item "C:\PostgreSQL\14\lib.backup_20260211_143000\*" -Destination "C:\PostgreSQL\14\lib\" -Force
  Start-Service postgresql-x64-14
  ```

### Version Mismatch Error
- Check `artifacts/postgresql_patch_complete.json` for expected version
- Verify correct package URL in `.gitlab-ci.yml`
- Ensure package filename matches version

### Orafce Extension Not Available
- Check `lib/orafce.dll` exists
- Check `share/extension/orafce.control` exists
- Try recreating extension:
  ```sql
  DROP EXTENSION IF EXISTS orafce CASCADE;
  CREATE EXTENSION orafce;
  ```

### Instance Skipped During Patching
- Check if major version package is configured
- Example: PostgreSQL 15 instance skipped if `cpu_PatchPostgreSQL_v15` not set
- Add missing version variable to `.gitlab-ci.yml`

---

## Environment Variables Used

- `cpu_PatchPostgreSQL` - PostgreSQL v14 binaries URL (required for v14 instances)
- `cpu_PatchPostgreSQL_v15` - PostgreSQL v15 binaries URL (required for v15 instances)
- `cpu_PatchPostgreSQL_Orafce` - Orafce extension package URL (optional)

Leave version variables empty to skip patching that major version.
Leave `cpu_PatchPostgreSQL_Orafce` empty to skip orafce deployment.

---

## Related Scripts

- `ci/Check-PostgreSQL-Installed.ps1` - Detection
- `ci/Patch-PostgreSQL.ps1` - Patching logic
- `ci/Verify-PostgreSQL-Patch.ps1` - Verification
- `lib/postgres_tools.psm1` - Utility functions

---

## Notes

- Supports multiple PostgreSQL instances on same server
- Supports multiple major versions (14, 15, etc.) in single pipeline run
- Each instance matched to correct version package automatically
- Orafce extension deployment is version-aware
- Binary backups deleted only after successful service start
- Works with PostgreSQL Enterprise and Community editions
