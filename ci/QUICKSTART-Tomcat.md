# Quick Start: Tomcat Patching with GitLab Runners

## Prerequisites Checklist

- [ ] GitLab runners configured with group tag and hostname tag
- [ ] `GITLAB_API_TOKEN` CI/CD variable configured
- [ ] Tomcat package uploaded to Artifactory
- [ ] `pack_tomcat.xml` metadata file in Artifactory
- [ ] Server backups completed
- [ ] Users notified of maintenance

## Quick Run

### Patch All Tomcat Domains on All Servers

1. Go to **CI/CD → Pipelines → Run Pipeline**
2. Set variables:
   ```
   ACTION: Patch Tomcat
   SERVER_GROUP_TAG: cyp-gen-windows
   cpu_PatchWebTier: https://artifactory.example.com/.../tomcat/9.0.90/
   cpu_DOMAIN: (leave empty)
   ```
3. Click **Run Pipeline**

### Patch Specific Domain on All Servers

1. Go to **CI/CD → Pipelines → Run Pipeline**
2. Set variables:
   ```
   ACTION: Patch Tomcat
   SERVER_GROUP_TAG: cyp-gen-windows
   cpu_PatchWebTier: https://artifactory.example.com/.../tomcat/9.0.90/
   cpu_DOMAIN: cv_main
   ```
3. Click **Run Pipeline**

## What Happens

```
┌─────────────────────────────────────────────┐
│ Orchestrator (cyp-gen-windows runner)       │
│ - Discovers all servers with group tag      │
│ - Triggers child pipeline per server        │
└─────────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
┌──────────────┐        ┌──────────────┐
│  SERVER01    │        │  SERVER02    │
└──────────────┘        └──────────────┘
        │                       │
        ▼                       ▼
  ┌─────────┐             ┌─────────┐
  │ Check   │             │ Check   │
  │ Tomcat  │             │ Tomcat  │
  └─────────┘             └─────────┘
        │                       │
        ▼                       ▼
  ┌─────────┐             ┌─────────┐
  │Validate │             │Validate │
  │ Domain  │             │ Domain  │
  └─────────┘             └─────────┘
        │                       │
        ▼                       ▼
  ┌─────────┐             ┌─────────┐
  │  Patch  │             │  Patch  │
  │ Tomcat  │             │ Tomcat  │
  └─────────┘             └─────────┘
        │                       │
        ▼                       ▼
  ┌─────────┐             ┌─────────┐
  │ Verify  │             │ Verify  │
  │  Patch  │             │  Patch  │
  └─────────┘             └─────────┘
```

## Expected Timeline

| Stage | Duration | Description |
|-------|----------|-------------|
| Orchestrate | 1-2 min | Runner discovery |
| Check | 1-2 min | Discover Tomcat |
| Validate | < 1 min | Validate domain |
| Patch | 5-10 min | Apply patch |
| Verify | 1-2 min | Verify success |

**Total per server**: ~10-15 minutes

## Common Scenarios

### Scenario 1: Patch Production Servers
```yaml
ACTION: Patch Tomcat
SERVER_GROUP_TAG: cyp-prod-windows
cpu_PatchWebTier: https://artifactory.example.com/.../tomcat/9.0.90/
cpu_DOMAIN: (empty - patches all)
```

### Scenario 2: Patch Test Environment Only
```yaml
ACTION: Patch Tomcat
SERVER_GROUP_TAG: cyp-test-windows
cpu_PatchWebTier: https://artifactory.example.com/.../tomcat/9.0.90/
cpu_DOMAIN: (empty)
```

### Scenario 3: Patch Single Domain Across Multiple Servers
```yaml
ACTION: Patch Tomcat
SERVER_GROUP_TAG: cyp-gen-windows
cpu_PatchWebTier: https://artifactory.example.com/.../tomcat/9.0.90/
cpu_DOMAIN: cv_main
```

## Monitoring Progress

### View Pipeline
1. Go to **CI/CD → Pipelines**
2. Click on your running pipeline
3. View progress by stage

### Check Individual Server
1. Click on a specific job (e.g., `patch_tomcat` for SERVER01)
2. View real-time logs
3. Download artifacts when complete

### Download Artifacts
1. Navigate to completed job
2. Click **Browse** under Job Artifacts
3. Download:
   - `tomcat_instances.json` - Discovered domains
   - `tomcat_verification.json` - Verification results

## Verification Checklist

After pipeline completes:

- [ ] All child pipelines succeeded (green)
- [ ] Verify job shows version match
- [ ] Services are running (check job logs)
- [ ] Download and review verification artifacts
- [ ] Test application functionality
- [ ] Check Tomcat logs for errors

## Rollback Procedure

If issues occur:

1. **Stop Tomcat Services**
   ```powershell
   Get-Service "Apache Tomcat *" | Stop-Service
   ```

2. **Restore Previous Version**
   ```powershell
   cd C:\ChildView\tomcat\{domain}
   Remove-Item bin -Recurse -Force
   Remove-Item lib -Recurse -Force
   Rename-Item bin_old bin
   Rename-Item lib_old lib
   ```

3. **Restart Services**
   ```powershell
   Get-Service "Apache Tomcat *" | Start-Service
   ```

## PowerShell Commands

### Check Current Tomcat Version
```powershell
Get-Content "C:\ChildView\tomcat\cv_main\RELEASE-NOTES" | Select-String "Version"
```

### Check Service Status
```powershell
Get-Service "Apache Tomcat *" | Format-Table Name, Status, DisplayName
```

### View Recent Tomcat Logs
```powershell
Get-Content "C:\ChildView\tomcat\cv_main\logs\catalina.*.log" -Tail 50
```

### Verify Patching History
```powershell
Get-ChildItem "C:\gitroot\cpu\artifacts\tomcat_*.json" | 
    Get-Content | ConvertFrom-Json | 
    Select-Object Hostname, PatchDate, @{N='Version';E={$_.ExpectedVersion}}
```

## Emergency Contacts

| Issue | Contact |
|-------|---------|
| Pipeline failures | CI/CD Team |
| Tomcat issues | WebTier Team |
| Artifactory access | DevOps Team |
| Emergency rollback | On-call Engineer |

## FAQ

**Q: Can I patch only one server?**  
A: Not directly. The pipeline targets all servers with the group tag. To patch one server, either:
- Create a unique group tag for that server
- Manually run the patch scripts on the server

**Q: What if a server is offline?**  
A: The pipeline only discovers active runners. Offline servers are automatically skipped.

**Q: Can I schedule patches?**  
A: Yes, use GitLab's pipeline schedules:
1. Go to **CI/CD → Schedules**
2. Click **New Schedule**
3. Configure schedule and variables

**Q: What if verification fails?**  
A: The pipeline will fail and stop. Review logs, fix issues, and re-run the pipeline.

**Q: Can I run in parallel?**  
A: Yes! Each server runs independently in parallel.

## See Also

- [Full Documentation](README-Tomcat.md)
- [Oracle Patching Guide](README.txt)
- [CI/CD Pipeline Overview](.gitlab-ci.yml)
