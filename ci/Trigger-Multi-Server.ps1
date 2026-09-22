<#
.SYNOPSIS
    Trigger child pipelines for each server in the group.

.DESCRIPTION
    This script creates child pipeline runs for each server hostname, ensuring
    each server runs the pipeline in isolation using its specific hostname tag.

.EXAMPLE
    .\Trigger-Multi-Server.ps1
    
.NOTES
    Author: Auto-generated
    Date: November 12, 2025
    NOT USED by .github/workflows/patch.yml - multi-server fan-out is now done via a
    GitHub Actions matrix (see server_labels input) instead of triggering child pipelines.
    Kept only for reference / GitLab rollback.
#>

[CmdletBinding()]
param()

# Load System.Web for URL encoding
Add-Type -AssemblyName System.Web

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Multi-Server Pipeline Orchestrator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get environment variables
$serverGroupTagRaw = $env:SERVER_GROUP_TAG
$action = $env:ACTION
$cpuPatchDB = $env:cpu_PatchDB
$cpuSID = $env:cpu_SID
$cpuPatchWebTier = $env:cpu_PatchWebTier
$cpuPatchMetabase = $env:cpu_PatchMetabase
$cpuPatchPostgreSQL = $env:cpu_PatchPostgreSQL
$cpuPatch7Zip = $env:cpu_Patch7Zip
$gitlabApiToken = $env:GITLAB_API_TOKEN

# Parse comma-separated tags
$serverGroupTags = $serverGroupTagRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

Write-Host "Configuration:" -ForegroundColor Cyan
if ($serverGroupTags.Count -gt 1) {
    Write-Host "  Server Group Tags: $($serverGroupTags -join ', ')" -ForegroundColor White
} else {
    Write-Host "  Server Group Tag: $($serverGroupTags[0])" -ForegroundColor White
}
Write-Host "  Action: $action" -ForegroundColor White
Write-Host "  cpu_PatchDB: $cpuPatchDB" -ForegroundColor White
Write-Host "  cpu_SID: $cpuSID" -ForegroundColor White
Write-Host "  cpu_PatchWebTier: $cpuPatchWebTier" -ForegroundColor White
Write-Host "  cpu_PatchMetabase: $cpuPatchMetabase" -ForegroundColor White
Write-Host "  cpu_PatchPostgreSQL: $cpuPatchPostgreSQL" -ForegroundColor White
Write-Host "  cpu_Patch7Zip: $cpuPatch7Zip" -ForegroundColor White
Write-Host ""

# Get GitLab API details
$gitlabUrl = $env:CI_SERVER_URL
$projectId = $env:CI_PROJECT_ID
$gitlabToken = if ($gitlabApiToken) { $gitlabApiToken } else { $env:CI_JOB_TOKEN }
$ref = $env:CI_COMMIT_REF_NAME

if ([string]::IsNullOrWhiteSpace($gitlabUrl) -or [string]::IsNullOrWhiteSpace($projectId)) {
    Write-Host "ERROR: GitLab CI environment variables not found" -ForegroundColor Red
    Write-Host "This script must run within a GitLab CI pipeline." -ForegroundColor Red
    exit 1
}

Write-Host "GitLab Configuration:" -ForegroundColor Cyan
Write-Host "  URL: $gitlabUrl" -ForegroundColor White
Write-Host "  Project ID: $projectId" -ForegroundColor White
Write-Host "  Ref: $ref" -ForegroundColor White
Write-Host ""

# Discover runners with the group tag
Write-Host "========================================" -ForegroundColor Cyan
if ($serverGroupTags.Count -gt 1) {
    Write-Host "Discovering Runners with Tags: $($serverGroupTags -join ', ')" -ForegroundColor Cyan
} else {
    Write-Host "Discovering Runners with Tag: $($serverGroupTags[0])" -ForegroundColor Cyan
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Store runner information including all tags
$runnerTagsMap = @{}

try {
    # Query each tag separately (tag_list is AND, not OR) and combine results
    $headers = @{
        "PRIVATE-TOKEN" = $gitlabToken
    }
    Write-Host "Querying GitLab API for active runners with tag(s)..." -ForegroundColor Cyan
    
    $allRunners = @{}  # Use hashtable to avoid duplicates (key = runner ID)
    foreach ($tag in $serverGroupTags) {
        Write-Host "  Querying tag: $tag" -ForegroundColor Gray
        
        # Handle pagination to get all runners
        $page = 1
        $perPage = 100
        $tagRunnerCount = 0
        
        do {
            $runnersApiUrl = "$($env:CI_API_V4_URL)/runners?scope=active&tag_list=$tag&per_page=$perPage&page=$page"
            Write-Host "    API URL (page $page): $runnersApiUrl" -ForegroundColor DarkGray
            
            $response = Invoke-WebRequest -Uri $runnersApiUrl -Method Get -Headers $headers
            $tagRunners = $response.Content | ConvertFrom-Json
            
            foreach ($runner in $tagRunners) {
                if (-not $allRunners.ContainsKey($runner.id)) {
                    $allRunners[$runner.id] = $runner
                    $tagRunnerCount++
                }
            }
            
            # Check if there are more pages
            $linkHeader = $response.Headers['Link']
            $hasNextPage = $linkHeader -and $linkHeader -match 'rel="next"'
            $page++
            
        } while ($hasNextPage)
        
        Write-Host "    Found: $tagRunnerCount runner(s)" -ForegroundColor Gray
    }
    
    $groupRunners = $allRunners.Values
    if ($groupRunners.Count -eq 0) {
        Write-Host "ERROR: No active runners found with tag(s): $($serverGroupTags -join ', ')" -ForegroundColor Red
        exit 1
    }
    Write-Host "✓ Found $($groupRunners.Count) unique runner(s) across all tags" -ForegroundColor Green
    Write-Host ""
    
    # Extract runner-id tags (unique identifier for each runner)
    $servers = @()
    $serverInfoMap = @{}  # Map runner-id to server info
    
    foreach ($runner in $groupRunners) {
        Write-Host "Runner: $($runner.description)" -ForegroundColor Cyan
        Write-Host "  ID: $($runner.id)" -ForegroundColor Gray
        
        # Fetch full runner details to get the tag list
        $runnerDetailUrl = "$($env:CI_API_V4_URL)/runners/$($runner.id)"
        Write-Host "  Fetching runner details from: $runnerDetailUrl" -ForegroundColor Gray
        
        try {
            $runnerDetails = Invoke-RestMethod -Uri $runnerDetailUrl -Method Get -Headers $headers
            $allTags = $runnerDetails.tag_list
            
            Write-Host "  Tags: $($allTags -join ', ')" -ForegroundColor Gray
            
            # Look for runner-id-* tag (unique identifier for each runner)
            $runnerIdTag = $allTags | Where-Object { $_ -like 'runner-id-*' } | Select-Object -First 1
            
            # Extract actual server hostname (typically lowercase and looks like a hostname)
            # Priority: look for tags that match common hostname patterns (server-name-##)
            # Exclude: group tags, runner-id-*, and common generic tags
            $possibleHostnames = $allTags | Where-Object { 
                $_ -notin $serverGroupTags -and 
                $_ -notlike 'runner-id-*' -and 
                $_ -notmatch '^(windows|internal|powershell|cyp-gen-.+|AppServer|WebServer|ChildView|TestAuto|TestManual|Nexus|DatabaseServer)$'
            }
            
            # Prefer tags that look like server names (contain hyphens and numbers)
            $hostnameTag = $possibleHostnames | Where-Object { $_ -match '^[a-z]+-[a-z]+-\d+$|^[a-z]+-[a-z]+\d+$' } | Select-Object -First 1
            
            # If no match found with that pattern, take the first remaining tag
            if (-not $hostnameTag) {
                $hostnameTag = $possibleHostnames | Select-Object -First 1
            }
            
            if ($runnerIdTag) {
                Write-Host "  ✓ Runner ID Tag: $runnerIdTag" -ForegroundColor Green
                if ($hostnameTag) {
                    Write-Host "  ✓ Hostname Tag: $hostnameTag" -ForegroundColor Green
                } else {
                    Write-Host "  ⚠ Warning: Could not determine hostname tag" -ForegroundColor Yellow
                }
                $servers += $runnerIdTag
                
                # Store all tags, description, and hostname for this runner
                $serverInfoMap[$runnerIdTag] = @{
                    AllTags = $allTags
                    Description = $runner.description
                    RunnerId = $runner.id
                    HostnameTag = $hostnameTag
                    ServerHostname = $hostnameTag  # For reporting compatibility
                }
                $runnerTagsMap[$runnerIdTag] = $allTags
            } else {
                Write-Host "  ⚠ Warning: No runner-id-* tag found for runner" -ForegroundColor Yellow
            }
            
        } catch {
            Write-Host "  ✗ ERROR: Failed to fetch runner details: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host ""
    }
    
    if ($servers.Count -eq 0) {
        Write-Host "ERROR: No valid server runner-id tags found" -ForegroundColor Red
        Write-Host "Runners must have both a group tag (from: $($serverGroupTags -join ', ')) and a unique runner-id-* tag." -ForegroundColor Yellow
        exit 1
    }
    
} catch {
    Write-Host "ERROR: Failed to query GitLab API for runners" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Note: Ensure you have a GITLAB_API_TOKEN with api scope, or use a Personal Access Token." -ForegroundColor Yellow
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Servers to Process: $($servers.Count)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
foreach ($server in $servers) {
    $serverInfo = $serverInfoMap[$server]
    $displayName = if ($serverInfo.HostnameTag) { "$server ($($serverInfo.HostnameTag))" } else { $server }
    Write-Host "  - $displayName" -ForegroundColor White
}
Write-Host ""

# Trigger child pipeline for each server
$triggeredPipelines = @()
$failedTriggers = @()

foreach ($server in $servers) {
    $serverInfo = $serverInfoMap[$server]
    $hostnameTag = $serverInfo.HostnameTag
    $displayName = if ($hostnameTag) { $hostnameTag } else { $server }
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Triggering Pipeline for: $displayName ($server)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Debug: Show server variable type and value
    Write-Host "DEBUG - Server variable details:" -ForegroundColor Magenta
    Write-Host "  Type: $($server.GetType().Name)" -ForegroundColor Gray
    Write-Host "  Length: $($server.Length)" -ForegroundColor Gray
    Write-Host "  Value: '$server'" -ForegroundColor Gray
    
    try {
        # Ensure server is treated as a single string value
        $serverTag = [string]$server
        
        # Determine which group tags this specific runner has (not all group tags)
        $runnerAllTags = $serverInfo.AllTags
        $runnerGroupTags = $runnerAllTags | Where-Object { $_ -in $serverGroupTags }
        $runnerGroupTagString = $runnerGroupTags -join ','
        
        # Build API URL - note: it's /pipeline (singular)
        # URL encode the project ID in case it contains special characters
        $encodedProjectId = [System.Web.HttpUtility]::UrlEncode($projectId)
        $apiUrl = "$gitlabUrl/api/v4/projects/$encodedProjectId/pipeline"
        
        # Build pipeline variables
        $variables = @(
            @{ key = "ACTION"; value = $action }
            @{ key = "SERVER_GROUP_TAG"; value = $runnerGroupTagString }
            @{ key = "CURRENT_SERVER_TAG"; value = $serverTag }
            @{ key = "cpu_PatchDB"; value = $cpuPatchDB }
            @{ key = "cpu_SID"; value = $cpuSID }
            @{ key = "cpu_PatchWebTier"; value = $cpuPatchWebTier }
            @{ key = "cpu_PatchMetabase"; value = $cpuPatchMetabase }
            @{ key = "cpu_PatchPostgreSQL"; value = $cpuPatchPostgreSQL }
            @{ key = "cpu_Patch7Zip"; value = $cpuPatch7Zip }
            @{ key = "cpu_RequiredFreeSpace"; value = $env:cpu_RequiredFreeSpace }
        )
        
        $body = @{
            ref = $ref
            variables = $variables
        } | ConvertTo-Json -Depth 10
        
        Write-Host "API URL: $apiUrl" -ForegroundColor Gray
        Write-Host "Request Body:" -ForegroundColor Gray
        Write-Host $body -ForegroundColor Gray
        Write-Host "Triggering child pipeline..." -ForegroundColor Cyan
        
        # Trigger the pipeline - use PRIVATE-TOKEN header instead of JOB-TOKEN
        $triggerHeaders = @{
            "PRIVATE-TOKEN" = $gitlabToken
            "Content-Type" = "application/json"
        }
        
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $triggerHeaders -Body $body
        
        $pipelineId = $response.id
        $pipelineUrl = $response.web_url
        
        Write-Host "✓ Pipeline triggered successfully" -ForegroundColor Green
        Write-Host "  Pipeline ID: $pipelineId" -ForegroundColor White
        Write-Host "  Pipeline URL: $pipelineUrl" -ForegroundColor White
        Write-Host ""
        
        $triggeredPipelines += @{
            Server = $serverTag
            ServerHostname = $hostnameTag
            PipelineId = $pipelineId
            PipelineUrl = $pipelineUrl
            OtherTags = $serverInfo.AllTags | Where-Object { $_ -notin $serverGroupTags -and $_ -notlike 'runner-id-*' }
        }
        
    } catch {
        Write-Host "✗ Failed to trigger pipeline for $server" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) {
            Write-Host "  Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
        }
        if ($_.Exception.Response) {
            Write-Host "  Status Code: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
        Write-Host ""
        
        $failedTriggers += $server
    }
}

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Orchestration Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total Servers: $($servers.Count)" -ForegroundColor White
Write-Host "Pipelines Triggered: $($triggeredPipelines.Count)" -ForegroundColor Green
Write-Host "Failed Triggers: $($failedTriggers.Count)" -ForegroundColor $(if ($failedTriggers.Count -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($triggeredPipelines.Count -gt 0) {
    Write-Host "Triggered Pipelines:" -ForegroundColor Cyan
    foreach ($pipeline in $triggeredPipelines) {
        Write-Host "  ✓ $($pipeline.Server): $($pipeline.PipelineUrl)" -ForegroundColor Green
    }
    Write-Host ""
}

if ($failedTriggers.Count -gt 0) {
    Write-Host "Failed Triggers:" -ForegroundColor Red
    foreach ($server in $failedTriggers) {
        Write-Host "  ✗ $server" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "WARNING: Some pipelines failed to trigger" -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ All server pipelines triggered successfully" -ForegroundColor Green
Write-Host "Monitor individual pipelines using the URLs above." -ForegroundColor Cyan

# Save triggered pipeline information for reporting
$reportData = @{
    ParentPipelineId = $env:CI_PIPELINE_ID
    ParentPipelineUrl = $env:CI_PIPELINE_URL
    ServerGroupTag = $serverGroupTagRaw
    ServerGroupTags = $serverGroupTags
    TriggerTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    TriggeredPipelines = $triggeredPipelines
    FailedTriggers = $failedTriggers
}

# Save to workspace artifacts directory
$workspaceArtifactsPath = Join-Path $PSScriptRoot "..\artifacts"
if (-not (Test-Path $workspaceArtifactsPath)) {
    New-Item -Path $workspaceArtifactsPath -ItemType Directory -Force | Out-Null
}

$reportFile = Join-Path $workspaceArtifactsPath "triggered_pipelines.json"
$reportData | ConvertTo-Json -Depth 10 | Set-Content -Path $reportFile -Encoding UTF8
Write-Host "Saved pipeline information to: $reportFile" -ForegroundColor Cyan

# Also save to shared config directory
$sharedReportPath = "D:\CACI\Config\cpu_Oraclepath"
if (-not (Test-Path $sharedReportPath)) {
    New-Item -Path $sharedReportPath -ItemType Directory -Force | Out-Null
}
$sharedReportFile = Join-Path $sharedReportPath "triggered_pipelines.json"
Copy-Item -Path $reportFile -Destination $sharedReportFile -Force
Write-Host "Copied to shared location: $sharedReportFile" -ForegroundColor Cyan

exit 0
