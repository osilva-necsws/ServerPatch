# Multi-Server Oracle Patching Pipeline

## Overview

This GitLab CI/CD pipeline automatically discovers and runs Oracle database patching across all servers in a specified group. Each server runs independently with full isolation using hostname tags.

## How It Works

### 1. Runner Discovery
- Pipeline queries GitLab API for all online runners with the specified group tag
- Extracts unique hostname tags from each runner (tags other than the group tag)
- Creates a list of target servers

### 2. Child Pipeline Triggering
- Triggers a separate child pipeline for each discovered server
- Each child pipeline uses both the group tag AND hostname tag
- Ensures execution only on the intended server

### 3. Isolated Execution
- Each server executes: check → validate → patch
- Independent artifacts and logs per server
- Graceful skipping if no databases or SID not found

## Prerequisites

### 1. GitLab Runner Tags
Each runner MUST have TWO tags:
- **Group tag**: e.g., `cyp-gen-windows`, `cyp-prod-windows`
- **Hostname tag**: e.g., `SERVER01`, `DBHOST-PROD-01`

Example runner configuration:
```toml
[[runners]]
  name = "Database Server 01"
  tags = ["cyp-gen-windows", "SERVER01"]
```

### 2. GitLab API Token
Required for runner discovery via API.

#### Create Personal Access Token:
1. Go to GitLab → User Settings → Access Tokens
2. Create token with:
   - **Name**: `Pipeline Runner Discovery`
   - **Scopes**: ✅ `api`, ✅ `read_api`
   - **Expiration**: Set as needed

#### Add to Project CI/CD Variables:
1. Go to Project → Settings → CI/CD → Variables
2. Add variable:
   - **Key**: `GITLAB_API_TOKEN`
   - **Value**: `<your-token>`
   - **Type**: Variable
   - **Protected**: ✅ Yes
   - **Masked**: ✅ Yes
   - **Expanded**: ✅ Yes

## Usage

### Run Oracle Patching on All Servers in Group

1. Navigate to: CI/CD → Pipelines → Run Pipeline
2. Select branch (e.g., `main`)
3. Set variables:

```yaml
ACTION: "Patch Oracle"
SERVER_GROUP_TAG: "cyp-gen-windows"     # Your group tag
RUN_PATCH: "false"                       # Set "true" when ready to patch
cpu_PatchDB: "RU_19.27"                  # Patch identifier
cpu_SID: "ORCL"                          # Database SID
```

4. Click **Run Pipeline**

### What Happens:

```
Parent Pipeline
    ↓
Orchestrator discovers: SERVER01, SERVER02, SERVER03 (via API)
    ↓
    ├── Child Pipeline → SERVER01
    │   └── check → validate → patch
    │
    ├── Child Pipeline → SERVER02
    │   └── check → validate → patch
    │
    └── Child Pipeline → SERVER03
        └── check → validate → patch
```

## Pipeline Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ACTION` | Yes | "Create Package" | "Patch Oracle" or "Create Package" |
| `SERVER_GROUP_TAG` | Yes | "cyp-gen-windows" | Group tag to target all servers |
| `RUN_PATCH` | Yes | "false" | Safety switch - set "true" to execute patch |
| `cpu_PatchDB` | For patching | "" | Oracle patch identifier (e.g., "RU_19.27") |
| `cpu_SID` | For patching | "" | Oracle database SID (e.g., "ORCL") |
| `GITLAB_API_TOKEN` | Yes | "" | API token for runner discovery (set in CI/CD variables) |

## Pipeline Stages

### Stage 1: Orchestrate
- **Job**: `trigger_multi_server`
- Discovers all runners with `SERVER_GROUP_TAG`
- Extracts hostname tags
- Triggers child pipeline for each server
- Shows summary of triggered pipelines

### Stage 2: Check (per server)
- **Job**: `check_oracle_installed`
- Detects Oracle databases on the server
- Creates `oracle_databases.json` artifact
- Creates marker if no databases found

### Stage 3: Validate (per server)
- **Job**: `validate_oracle_sid`
- Validates `cpu_SID` matches a running database
- Creates marker if SID not found
- Skips if no databases exist

### Stage 4: Patch (per server)
- **Job**: `patch_oracle`
- Only runs if `RUN_PATCH == "true"`
- Executes `Patch_database.bat`
- Skips gracefully if validation failed

## Safety Features

✅ **Manual-only execution** - Pipeline only runs via web UI  
✅ **RUN_PATCH safety switch** - Prevents accidental patching  
✅ **Per-server isolation** - Hostname tags ensure correct server  
✅ **Automatic discovery** - No manual server list maintenance  
✅ **Graceful failures** - Skips servers with no databases or wrong SID  
✅ **Independent execution** - Each server's pipeline is separate  

## Monitoring

### View Parent Pipeline
- Shows orchestrator job with list of triggered child pipelines
- Links to each server's child pipeline

### View Individual Server Pipeline
- Click on child pipeline URL from orchestrator output
- See server-specific results: check → validate → patch
- Review artifacts: `oracle_databases.json`

## Troubleshooting

### No runners discovered
**Cause**: No runners with specified group tag  
**Solution**: 
- Verify `SERVER_GROUP_TAG` is correct
- Check runners are online: Settings → CI/CD → Runners
- Ensure runners have the group tag configured

### API authentication failed
**Cause**: Missing or invalid `GITLAB_API_TOKEN`  
**Solution**:
- Create Personal Access Token with `api` scope
- Add to project CI/CD variables as `GITLAB_API_TOKEN`
- Ensure token is not expired

### Child pipeline runs on wrong server
**Cause**: Runner missing hostname tag  
**Solution**:
- Each runner MUST have unique hostname tag
- Edit runner configuration to add hostname tag
- Restart GitLab Runner service

### No databases found on server
**Result**: Pipeline completes successfully, but skips patch jobs  
**This is expected** - Not an error if server has no Oracle databases

### SID not found
**Result**: Pipeline completes successfully, but skips patch job  
**Action**: Verify `cpu_SID` matches actual database SID on target servers

## Example Runner Configuration

### config.toml
```toml
concurrent = 1

[[runners]]
  name = "Database Server 01 - Production"
  url = "https://gitlab.company.com/"
  token = "..."
  executor = "shell"
  tags = ["cyp-prod-windows", "DBPROD01"]
  shell = "pwsh"

[[runners]]
  name = "Database Server 02 - Production"
  url = "https://gitlab.company.com/"
  token = "..."
  executor = "shell"
  tags = ["cyp-prod-windows", "DBPROD02"]
  shell = "pwsh"
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│ Parent Pipeline (Manual Trigger)               │
│ - User sets: SERVER_GROUP_TAG                  │
│ - Runs on: Any runner in group                 │
└────────────────┬────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────────────┐
│ Orchestrator (trigger_multi_server)            │
│ - Queries GitLab API for runners               │
│ - Finds: SERVER01, SERVER02, SERVER03          │
│ - Triggers 3 child pipelines                   │
└────────┬────────────┬───────────────┬───────────┘
         ↓            ↓               ↓
    ┌────────┐   ┌────────┐     ┌────────┐
    │Child #1│   │Child #2│     │Child #3│
    │SERVER01│   │SERVER02│     │SERVER03│
    └────────┘   └────────┘     └────────┘
    Tags:        Tags:          Tags:
    - group      - group        - group
    - SERVER01   - SERVER02     - SERVER03
```

## Related Documentation

- [Check-OracleDatabases.ps1](../../docs/cpuInstaller/ci/Check-OracleDatabases.md)
- [Check-Oracle-Installed.ps1](../../docs/cpuInstaller/ci/Check-Oracle-Installed.md)
- [Validate-Oracle-SID.ps1](../../docs/cpuInstaller/ci/Validate-Oracle-SID.md)
- [Patch-Oracle.ps1](../../docs/cpuInstaller/ci/Patch-Oracle.md)
- [Trigger-Multi-Server.ps1](../../docs/cpuInstaller/ci/Trigger-Multi-Server.md)

## Support

For issues or questions:
1. Check orchestrator job output for triggered pipeline URLs
2. Review individual server pipeline logs
3. Verify runner configuration and tags
4. Ensure `GITLAB_API_TOKEN` has correct permissions
