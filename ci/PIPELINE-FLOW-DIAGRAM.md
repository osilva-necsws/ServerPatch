# Tomcat GitLab CI/CD Pipeline Flow

## Complete Pipeline Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    USER TRIGGERS PIPELINE                            │
│  Action: "Patch Tomcat"                                             │
│  SERVER_GROUP_TAG: "cyp-gen-windows"                                │
│  cpu_PatchWebTier: "https://artifactory.../tomcat/9.0.90/"         │
│  cpu_DOMAIN: "" (empty = all domains)                               │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    STAGE: ORCHESTRATE                                │
│  Job: trigger_multi_server                                          │
│  Runner: cyp-gen-windows (orchestrator)                             │
│  ┌───────────────────────────────────────────────────────────┐     │
│  │ 1. Query GitLab API for runners with group tag           │     │
│  │ 2. Extract hostname tags from each runner                │     │
│  │ 3. Create child pipeline for each server:                │     │
│  │    - SERVER01 → Tags: [cyp-gen-windows, SERVER01]        │     │
│  │    - SERVER02 → Tags: [cyp-gen-windows, SERVER02]        │     │
│  │    - SERVER03 → Tags: [cyp-gen-windows, SERVER03]        │     │
│  └───────────────────────────────────────────────────────────┘     │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                 ┌─────────────┼─────────────┐
                 │             │             │
                 ▼             ▼             ▼
      ┌────────────────┐ ┌────────────────┐ ┌────────────────┐
      │   SERVER01     │ │   SERVER02     │ │   SERVER03     │
      │  (Isolated)    │ │  (Isolated)    │ │  (Isolated)    │
      └────────────────┘ └────────────────┘ └────────────────┘
             │                  │                   │
             │                  │                   │
             ▼                  ▼                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        STAGE: CHECK                                  │
│  Job: check_tomcat_installed                                        │
│  ┌───────────────────────────────────────────────────────────┐     │
│  │ 1. Run audit_get.ps1 to generate Platform_config.xml     │     │
│  │ 2. Parse XML for web service components                  │     │
│  │ 3. Extract domain information:                           │     │
│  │    - Domain name (e.g., cv_main)                         │     │
│  │    - Home directory                                      │     │
│  │    - Base directory                                      │     │
│  │    - Current version                                     │     │
│  │ 4. Create artifact: tomcat_instances.json                │     │
│  │ 5. If no Tomcat found → Create no_tomcat_found.marker    │     │
│  └───────────────────────────────────────────────────────────┘     │
│                                                                      │
│  Output Examples:                                                   │
│  ✓ Found: cv_main, cv_test @ C:\ChildView\tomcat\                  │
│  ⚠ None found: Creates marker, skips remaining stages               │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      STAGE: VALIDATE                                 │
│  Job: validate_tomcat_domain                                        │
│  ┌───────────────────────────────────────────────────────────┐     │
│  │ 1. Load tomcat_instances.json from previous job          │     │
│  │ 2. Check cpu_DOMAIN variable:                            │     │
│  │    - Empty → Show all domains, allow all to patch        │     │
│  │    - Specified → Validate domain exists                  │     │
│  │ 3. If domain not found → Create domain_not_found.marker  │     │
│  │ 4. Display domain details if valid                       │     │
│  └───────────────────────────────────────────────────────────┘     │
│                                                                      │
│  Decision Logic:                                                    │
│  ✓ cpu_DOMAIN="" → Proceed to patch ALL domains                    │
│  ✓ cpu_DOMAIN="cv_main" + exists → Proceed to patch cv_main        │
│  ⚠ cpu_DOMAIN="invalid" → Create marker, skip patch                │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        STAGE: PATCH                                  │
│  Job: patch_tomcat                                                  │
│  ┌───────────────────────────────────────────────────────────┐     │
│  │ Phase 1: Download Package                                │     │
│  │   - Extract filename from cpu_PatchWebTier URL           │     │
│  │   - Check if package already downloaded                  │     │
│  │   - Download Tomcat ZIP file from Artifactory            │     │
│  │   - Calculate MD5 checksum (for logging only)            │     │
│  │                                                           │     │
│  │ Phase 2: Pre-Check                                       │     │
│  │   - Extract version from package name                    │     │
│  │   - Check if already at this version                     │     │
│  │   - Skip if already patched                              │     │
│  │                                                           │     │
│  │ Phase 3: Get Domain Details                              │     │
│  │   - Call webtier_details() to load all domains           │     │
│  │   - All domains are always patched together              │     │
│  │                                                           │     │
│  │ Phase 4: Application Replacement                         │     │
│  │   - For each domain:                                     │     │
│  │     * Run tomcat_app_replacement()                       │     │
│  │     * Process web applications                           │     │
│  │                                                           │     │
│  │ Phase 5: Update Tomcat (via update_tomcat)               │     │
│  │   - Stop all Tomcat services                             │     │
│  │   - Backup: bin → bin_old, lib → lib_old                 │     │
│  │   - Extract new bin/ and lib/ from ZIP                   │     │
│  │   - Remove old documentation files                       │     │
│  │   - For each domain:                                     │     │
│  │     * Remove unnecessary webapps (docs, manager, etc.)   │     │
│  │     * Remove default index.jsp                           │     │
│  │   - Restart all services                                 │     │
│  │                                                           │     │
│  │ Phase 6: Create Completion Artifact                      │     │
│  │   - Save tomcat_patch_complete.json                      │     │
│  └───────────────────────────────────────────────────────────┘     │
│                                                                      │
│  ⚠ CRITICAL: Services stopped during update!                        │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    STAGE: POST-PATCH                                 │
│  Job: verify_tomcat_patch                                           │
│  ┌───────────────────────────────────────────────────────────┐     │
│  │ 1. Load patch completion data                            │     │
│  │ 2. Determine expected version from package               │     │
│  │ 3. Re-run audit to get current state                     │     │
│  │ 4. For each patched domain, verify:                      │     │
│  │    ✓ Domain directory exists                             │     │
│  │    ✓ RELEASE-NOTES contains correct version              │     │
│  │    ✓ Windows service exists and is running               │     │
│  │    ✓ bin/ directory exists                               │     │
│  │    ✓ lib/ directory exists                               │     │
│  │ 5. Create verification artifact                          │     │
│  │ 6. Exit 0 if all checks pass, exit 1 if any fail         │     │
│  └───────────────────────────────────────────────────────────┘     │
│                                                                      │
│  Verification Results:                                              │
│  ✓ All pass → Pipeline succeeds                                     │
│  ✗ Any fail → Pipeline fails, requires investigation                │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      STAGE: REPORT                                   │
│  Job: generate_report                                               │
│  Runner: cyp-gen-windows (orchestrator)                             │
│  ┌───────────────────────────────────────────────────────────┐     │
│  │ 1. Collect results from all child pipelines              │     │
│  │ 2. Generate HTML summary report                          │     │
│  │ 3. Send email notification (if configured)               │     │
│  │ 4. Save report artifact                                  │     │
│  └───────────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────┘


## Artifacts Flow

┌─────────────────────────────────────────────────────────────────────┐
│                    ARTIFACTS PER SERVER                              │
│                                                                      │
│  check_tomcat_installed:                                            │
│  └─ artifacts/tomcat_instances.json                                 │
│     {                                                                │
│       "Hostname": "SERVER01",                                       │
│       "DiscoveryDate": "2026-01-06 14:30:00",                       │
│       "TomcatDomains": [                                            │
│         {                                                            │
│           "Name": "cv_main",                                        │
│           "Home": "C:\\ChildView\\tomcat\\cv_main",                 │
│           "Version": "9.0.85"                                       │
│         }                                                            │
│       ]                                                              │
│     }                                                                │
│                                                                      │
│  patch_tomcat:                                                      │
│  └─ artifacts/tomcat_patch_complete.json                            │
│     {                                                                │
│       "Hostname": "SERVER01",                                       │
│       "PatchDate": "2026-01-06 14:40:00",                           │
│       "PatchedDomains": ["cv_main"],                                │
│       "TomcatPackage": "apache-tomcat-9.0.90.zip"                   │
│     }                                                                │
│                                                                      │
│  verify_tomcat_patch:                                               │
│  └─ artifacts/tomcat_verification.json                              │
│     {                                                                │
│       "Hostname": "SERVER01",                                       │
│       "VerificationPassed": true,                                   │
│       "ExpectedVersion": "9.0.90",                                  │
│       "DomainResults": [                                            │
│         {                                                            │
│           "Domain": "cv_main",                                      │
│           "Verified": true,                                         │
│           "Version": "9.0.90",                                      │
│           "ServiceRunning": true                                    │
│         }                                                            │
│       ]                                                              │
│     }                                                                │
└─────────────────────────────────────────────────────────────────────┘


## Error Handling Flow

┌─────────────────────────────────────────────────────────────────────┐
│                    ERROR SCENARIOS                                   │
│                                                                      │
│  Scenario 1: No Tomcat Found                                        │
│  check_tomcat_installed → Creates no_tomcat_found.marker            │
│  validate_tomcat_domain → Skips (exit 0)                            │
│  patch_tomcat → Skips (exit 0)                                      │
│  Result: ✓ Pipeline succeeds but nothing patched                    │
│                                                                      │
│  Scenario 2: Domain Not Found                                       │
│  check_tomcat_installed → ✓ Finds domains                           │
│  validate_tomcat_domain → Creates domain_not_found.marker           │
│  patch_tomcat → Skips (exit 0)                                      │
│  Result: ✓ Pipeline succeeds but nothing patched                    │
│                                                                      │
│  Scenario 3: Already Patched                                        │
│  check_tomcat_installed → ✓ Finds domains                           │
│  validate_tomcat_domain → ✓ Domain valid                            │
│  patch_tomcat → Detects version match → Skips (exit 0)              │
│  Result: ✓ Pipeline succeeds, no changes needed                     │
│                                                                      │
│  Scenario 4: Download Failure                                       │
│  patch_tomcat → Cannot download ZIP → Exit 1                        │
│  Result: ✗ Pipeline fails, no changes made                          │
│                                                                      │
│  Scenario 5: MD5 Mismatch                                           │
│  patch_tomcat → MD5 verification fails → Exit 1                     │
│  Result: ✗ Pipeline fails, no changes made                          │
│                                                                      │
│  Scenario 6: Verification Failure                                   │
│  patch_tomcat → ✓ Completes                                         │
│  verify_tomcat_patch → Version mismatch or service down → Exit 1    │
│  Result: ✗ Pipeline fails, requires investigation                   │
└─────────────────────────────────────────────────────────────────────┘


## Security & Safety Features

┌─────────────────────────────────────────────────────────────────────┐
│                    SAFETY MECHANISMS                                 │
│                                                                      │
│  1. Pre-Patch Checks:                                               │
│     ✓ MD5 checksum verification                                     │
│     ✓ Version comparison (skip if already patched)                  │
│     ✓ Domain existence validation                                   │
│                                                                      │
│  2. Backup Strategy:                                                │
│     ✓ bin → bin_old (previous version retained)                     │
│     ✓ lib → lib_old (previous version retained)                     │
│     ✓ Easy rollback available                                       │
│                                                                      │
│  3. Post-Patch Verification:                                        │
│     ✓ Version check via RELEASE-NOTES                               │
│     ✓ Service status check                                          │
│     ✓ Critical directory validation                                 │
│                                                                      │
│  4. Isolation:                                                      │
│     ✓ Each server runs independently                                │
│     ✓ One server failure doesn't affect others                      │
│     ✓ Separate artifacts per server                                 │
│                                                                      │
│  5. Audit Trail:                                                    │
│     ✓ All actions logged in GitLab                                  │
│     ✓ Artifacts preserved for 7 days                                │
│     ✓ Full traceability                                             │
└─────────────────────────────────────────────────────────────────────┘
```

## Visual Summary

This pipeline provides:
- ✅ **Automated discovery** of Tomcat instances across multiple servers
- ✅ **Parallel execution** for efficiency
- ✅ **Safety checks** at every stage
- ✅ **Graceful handling** of edge cases
- ✅ **Comprehensive verification** of patch success
- ✅ **Full audit trail** via GitLab and artifacts
- ✅ **Flexible filtering** by domain
- ✅ **Easy rollback** with retained backups
