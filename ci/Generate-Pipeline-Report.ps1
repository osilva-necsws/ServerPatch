<#
.SYNOPSIS
    Generate and email a report of all child pipeline executions.

.DESCRIPTION
    Collects status information for all child pipelines triggered by the orchestrator,
    generates an HTML email report, and sends it via SMTP.

.EXAMPLE
    .\Generate-Pipeline-Report.ps1
    
.NOTES
    Author: Auto-generated
    Date: November 13, 2025
    NOT USED by .github/workflows/patch.yml - GitHub Actions runs all servers as matrix jobs
    in one workflow run, so each job's own actions/upload-artifact output (visible in the
    run summary) replaces this GitLab-Jobs-API polling script. Kept only for reference / GitLab rollback.
#>

[CmdletBinding()]
param()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Pipeline Report Generator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$reportEmailTo = $env:REPORT_EMAIL_TO
$reportEmailFrom = $env:REPORT_EMAIL_FROM
$smtpServer = $env:SMTP_SERVER
$gitlabToken = $env:GITLAB_API_TOKEN
$action = $env:ACTION  # "Patch Oracle", "Patch Tomcat", "Patch Metabase", or "Patch PostgreSQL"
$isTomcatPatching = $action -eq "Patch Tomcat"
$isMetabasePatching = $action -eq "Patch Metabase"
$isPostgreSQLPatching = $action -eq "Patch PostgreSQL"
$isApachePatching = $action -eq "Patch Apache"
$is7ZipPatching = $action -eq "Patch 7-Zip"

# Validate configuration
if ([string]::IsNullOrWhiteSpace($reportEmailTo)) {
    Write-Host "⚠ REPORT_EMAIL_TO not configured - skipping email report" -ForegroundColor Yellow
    Write-Host "Report will be generated but not sent" -ForegroundColor Yellow
    $sendEmail = $false
} else {
    $sendEmail = $true
}

# Load triggered pipeline information
$reportFile = Join-Path $PSScriptRoot "..\artifacts\triggered_pipelines.json"
if (-not (Test-Path $reportFile)) {
    Write-Host "✗ ERROR: Pipeline information file not found: $reportFile" -ForegroundColor Red
    Write-Host "The trigger_multi_server job may have failed or not run." -ForegroundColor Yellow
    exit 1
}

Write-Host "Loading pipeline information from: $reportFile" -ForegroundColor Cyan
$reportData = Get-Content -Path $reportFile -Raw | ConvertFrom-Json

Write-Host "Parent Pipeline: $($reportData.ParentPipelineUrl)" -ForegroundColor White
Write-Host "Server Group: $($reportData.ServerGroupTag)" -ForegroundColor White
Write-Host "Triggered: $($reportData.TriggerTime)" -ForegroundColor White
Write-Host "Child Pipelines: $($reportData.TriggeredPipelines.Count)" -ForegroundColor White
Write-Host ""

$headers = @{
    "PRIVATE-TOKEN" = $gitlabToken
}

# Wait for all child pipelines to complete
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Waiting for Child Pipelines to Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$maxWaitMinutes = 160  # Maximum wait time: 2 hours 40 minutes (gives buffer for 3h job timeout)
$checkIntervalSeconds = 30  # Check status every 30 seconds
$startTime = Get-Date
$allComplete = $false

# Track which pipelines are already finished to avoid redundant API calls
$finishedPipelines = @{}

while (-not $allComplete) {
    $elapsed = (Get-Date) - $startTime
    if ($elapsed.TotalMinutes -gt $maxWaitMinutes) {
        Write-Host "⚠ Maximum wait time of $maxWaitMinutes minutes exceeded" -ForegroundColor Yellow
        Write-Host "Generating report with current status..." -ForegroundColor Yellow
        break
    }
    
    $runningCount = 0
    $completedCount = 0
    
    foreach ($pipeline in $reportData.TriggeredPipelines) {
        $pipelineId = $pipeline.PipelineId
        
        if ($finishedPipelines.ContainsKey($pipelineId)) {
            $completedCount++
            continue
        }

        try {
            $apiUrl = "$($env:CI_API_V4_URL)/projects/$($env:CI_PROJECT_ID)/pipelines/$pipelineId"
            $pipelineInfo = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers
            
            $status = $pipelineInfo.status
            
            if ($status -in @("running", "pending", "created")) {
                $runningCount++
            } else {
                $completedCount++
                $finishedPipelines[$pipelineId] = $status
            }
        } catch {
            Write-Host "⚠ Failed to check status for $($pipeline.Server): $($_.Exception.Message)" -ForegroundColor Yellow
            $completedCount++  # Count as complete if we can't check status
        }
    }
    
    $totalPipelines = $reportData.TriggeredPipelines.Count
    Write-Host "Status: $completedCount/$totalPipelines completed, $runningCount running (elapsed: $([math]::Round($elapsed.TotalMinutes, 1)) min)" -ForegroundColor Cyan
    
    if ($runningCount -eq 0) {
        Write-Host "✓ All child pipelines have completed" -ForegroundColor Green
        $allComplete = $true
    } else {
        Write-Host "Waiting $checkIntervalSeconds seconds before next check..." -ForegroundColor Gray
        Start-Sleep -Seconds $checkIntervalSeconds
    }
}

Write-Host ""

# Collect status for each pipeline
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Collecting Final Pipeline Status" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$pipelineStatuses = @()

foreach ($pipeline in $reportData.TriggeredPipelines) {
    $server = $pipeline.Server
    $pipelineId = $pipeline.PipelineId
    $pipelineUrl = $pipeline.PipelineUrl
    
    Write-Host "Checking pipeline for: $server" -ForegroundColor Cyan
    Write-Host "  Pipeline ID: $pipelineId" -ForegroundColor Gray
    
    try {
        # Get pipeline status
        $apiUrl = "$($env:CI_API_V4_URL)/projects/$($env:CI_PROJECT_ID)/pipelines/$pipelineId"
        $pipelineInfo = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers
        
        $status = $pipelineInfo.status
        $startedAt = $pipelineInfo.started_at
        $finishedAt = $pipelineInfo.finished_at
        $duration = $pipelineInfo.duration
        
        Write-Host "  Status: $status" -ForegroundColor $(
            switch ($status) {
                "success" { "Green" }
                "failed" { "Red" }
                "running" { "Yellow" }
                "pending" { "Gray" }
                default { "White" }
            }
        )
        
        # Get job details for more information
        $jobsUrl = "$($env:CI_API_V4_URL)/projects/$($env:CI_PROJECT_ID)/pipelines/$pipelineId/jobs"
        $jobs = Invoke-RestMethod -Uri $jobsUrl -Method Get -Headers $headers
        
        $failedJobs = $jobs | Where-Object { $_.status -eq "failed" }
        
        # Try to get verification report artifact
        $verificationData = $null
        if ($isTomcatPatching) {
            # First check if Tomcat was even found on this server
            $checkJob = $jobs | Where-Object { $_.name -eq "check_tomcat_installed" }
            $noTomcatFound = $false
            
            if ($checkJob) {
                try {
                    $tomcatInstancesUrl = "$($env:CI_API_V4_URL)/projects/$($env:CI_PROJECT_ID)/jobs/$($checkJob.id)/artifacts/artifacts/tomcat_instances.json"
                    Write-Host "  Fetching Tomcat instances from: $tomcatInstancesUrl" -ForegroundColor Gray
                    $tomcatInstancesJson = Invoke-RestMethod -Uri $tomcatInstancesUrl -Method Get -Headers $headers
                    
                    if ($tomcatInstancesJson.TomcatFound -eq $false) {
                        $noTomcatFound = $true
                        $verificationData = @{
                            NoTomcatFound = $true
                            Message = $tomcatInstancesJson.Message
                            Hostname = $tomcatInstancesJson.Hostname
                            DiscoveryDate = $tomcatInstancesJson.DiscoveryDate
                        }
                        Write-Host "  ℹ No Tomcat instances found on this server" -ForegroundColor Cyan
                    }
                } catch {
                    Write-Host "  ⚠ Could not retrieve Tomcat instances data: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            
            # Only try to get verification if Tomcat was found
            if (-not $noTomcatFound) {
                $verifyJob = $jobs | Where-Object { $_.name -eq "verify_tomcat_patch" -and $_.status -eq "success" }
                if ($verifyJob) {
                    try {
                        $artifactsUrl = "$($env:CI_API_V4_URL)/projects/$($env:CI_PROJECT_ID)/jobs/$($verifyJob.id)/artifacts/artifacts/tomcat_verification.json"
                        Write-Host "  Fetching Tomcat verification from: $artifactsUrl" -ForegroundColor Gray
                        $verificationJson = Invoke-RestMethod -Uri $artifactsUrl -Method Get -Headers $headers
                        $verificationData = $verificationJson
                        Write-Host "  ✓ Retrieved Tomcat verification data" -ForegroundColor Green
                    } catch {
                        Write-Host "  ⚠ Could not retrieve Tomcat verification data: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "  ⚠ No successful verify_tomcat_patch job found" -ForegroundColor Yellow
                }
            }
        } elseif ($isMetabasePatching) {
            # First check if Metabase was even found on this server
            $checkJob = $jobs | Where-Object { $_.name -eq "check_metabase_installed" }
            $noMetabaseFound = $false
            
            if ($checkJob) {
                try {
                    $metabaseInstanceUrl = "$($env:CI_API_V4_URL)/projects/$($env:CI_PROJECT_ID)/jobs/$($checkJob.id)/artifacts/artifacts/metabase_instance.json"
                    Write-Host "  Fetching Metabase instances from: $metabaseInstanceUrl" -ForegroundColor Gray
                    $metabaseInstanceJson = Invoke-RestMethod -Uri $metabaseInstanceUrl -Method Get -Headers $headers
                    
                    if ($metabaseInstanceJson.MetabaseFound -eq $false) {
                        $noMetabaseFound = $true
                        $verificationData = @{
                            NoMetabaseFound = $true
                            Message = $metabaseInstanceJson.Message
                            Hostname = $metabaseInstanceJson.Hostname
                            Timestamp = $metabaseInstanceJson.Timestamp
                        }
                        Write-Host "  ℹ No Metabase instances found on this server" -ForegroundColor Cyan
                    }
                } catch {
                    Write-Host "  ⚠ Could not retrieve Metabase instances data: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            
            # Only try to get verification if Metabase was found
            if (-not $noMetabaseFound) {
                $verifyJob = $jobs | Where-Object { $_.name -eq "verify_metabase_patch" -and $_.status -eq "success" }
                if ($verifyJob) {
                    try {
                        $artifactsUrl = "$($env:CI_API_V4_URL)/projects/$($env:CI_PROJECT_ID)/jobs/$($verifyJob.id)/artifacts/artifacts/metabase_verification.json"
                        Write-Host "  Fetching Metabase verification from: $artifactsUrl" -ForegroundColor Gray
                        $verificationJson = Invoke-RestMethod -Uri $artifactsUrl -Method Get -Headers $headers
                        $verificationData = $verificationJson
                        Write-Host "  ✓ Retrieved Metabase verification data" -ForegroundColor Green
                    } catch {
                        Write-Host "  ⚠ Could not retrieve Metabase verification data: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "  ⚠ No successful verify_metabase_patch job found" -ForegroundColor Yellow
                }
            }
        } elseif ($isPostgreSQLPatching) {
            # First check if PostgreSQL was even found on this server
            $checkJob = $jobs | Where-Object { $_.name -eq "check_postgresql_installed" }
            $noPostgreSQLFound = $false
            
            if ($checkJob) {
                try {
                    $postgresqlInstanceUrl = "$($env:CI_API_V4_URL)/projects/$($env:CI_PROJECT_ID)/jobs/$($checkJob.id)/artifacts/artifacts/postgresql_instance.json"
                    Write-Host "  Fetching PostgreSQL instances from: $postgresqlInstanceUrl" -ForegroundColor Gray
                    $postgresqlInstanceJson = Invoke-RestMethod -Uri $postgresqlInstanceUrl -Method Get -Headers $headers
                    
                    if ($postgresqlInstanceJson.PostgreSQLFound -eq $false) {
                        $noPostgreSQLFound = $true
                        $verificationData = @{
                            NoPostgreSQLFound = $true
                            Message = $postgresqlInstanceJson.Message
                            Hostname = $postgresqlInstanceJson.Hostname
                            DiscoveryDate = $postgresqlInstanceJson.DiscoveryDate
                        }
                        Write-Host "  ℹ No PostgreSQL instances found on this server" -ForegroundColor Cyan
                    }
                } catch {
                    Write-Host "  ⚠ Could not retrieve PostgreSQL instances data: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            
            # Only try to get verification if PostgreSQL was found
            if (-not $noPostgreSQLFound) {
                # Get patch completion data (contains skipped instances info)
                $patchJob = $jobs | Where-Object { $_.name -eq "patch_postgresql" }
                $patchData = $null
                if ($patchJob) {
                    try {
                        $patchArtifactsUrl = "$($env:CI_API_V4_URL)/projects/$($env:CI_PROJECT_ID)/jobs/$($patchJob.id)/artifacts/artifacts/postgresql_patch_complete.json"
                        Write-Host "  Fetching PostgreSQL patch data from: $patchArtifactsUrl" -ForegroundColor Gray
                        $patchData = Invoke-RestMethod -Uri $patchArtifactsUrl -Method Get -Headers $headers
                        Write-Host "  ✓ Retrieved PostgreSQL patch data" -ForegroundColor Green
                    } catch {
                        Write-Host "  ⚠ Could not retrieve PostgreSQL patch data: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
                
                $verifyJob = $jobs | Where-Object { $_.name -eq "verify_postgresql_patch" -and $_.status -eq "success" }
                if ($verifyJob) {
                    try {
                        $artifactsUrl = "$($env:CI_API_V4_URL)/projects/$($env:CI_PROJECT_ID)/jobs/$($verifyJob.id)/artifacts/artifacts/postgresql_verification.json"
                        Write-Host "  Fetching PostgreSQL verification from: $artifactsUrl" -ForegroundColor Gray
                        $verificationJson = Invoke-RestMethod -Uri $artifactsUrl -Method Get -Headers $headers
                        $verificationData = $verificationJson
                        
                        # Add skipped instances from patch data to verification data
                        if ($patchData -and $patchData.SkippedInstances) {
                            $verificationData | Add-Member -NotePropertyName "SkippedInstances" -NotePropertyValue $patchData.SkippedInstances -Force
                            $verificationData | Add-Member -NotePropertyName "SkippedCount" -NotePropertyValue $patchData.SkippedCount -Force
                        }
                        
                        Write-Host "  ✓ Retrieved PostgreSQL verification data" -ForegroundColor Green
                    } catch {
                        Write-Host "  ⚠ Could not retrieve PostgreSQL verification data: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "  ⚠ No successful verify_postgresql_patch job found" -ForegroundColor Yellow
                }
            }
        } elseif ($isApachePatching) {
            # Look for apache verification artifact
            $verifyJob = $jobs | Where-Object { $_.name -eq "verify_apache_patch" -and $_.status -eq "success" }
            if ($verifyJob) {
                try {
                    $artifactsUrl = "$($env:CI_API_V4_URL)/projects/$($env:CI_PROJECT_ID)/jobs/$($verifyJob.id)/artifacts/artifacts/apache_verification.json"
                    Write-Host "  Fetching Apache verification from: $artifactsUrl" -ForegroundColor Gray
                    $verificationJson = Invoke-RestMethod -Uri $artifactsUrl -Method Get -Headers $headers
                    $verificationData = $verificationJson
                    Write-Host "  ✓ Retrieved Apache verification data" -ForegroundColor Green
                } catch {
                    Write-Host "  ⚠ Could not retrieve Apache verification data: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  ⚠ No successful verify_apache_patch job found" -ForegroundColor Yellow
            }
        } elseif ($is7ZipPatching) {
            # Look for 7-Zip patch artifact
            $patchJob = $jobs | Where-Object { $_.name -eq "patch_7zip" -and $_.status -eq "success" }
            if ($patchJob) {
                try {
                    $artifactsUrl = "$($env:CI_API_V4_URL)/projects/$($env:CI_PROJECT_ID)/jobs/$($patchJob.id)/artifacts/artifacts/7zip_patch_complete.json"
                    Write-Host "  Fetching 7-Zip patch data from: $artifactsUrl" -ForegroundColor Gray
                    $patchJson = Invoke-RestMethod -Uri $artifactsUrl -Method Get -Headers $headers
                    $patchData = $patchJson
                    Write-Host "  ✓ Retrieved 7-Zip patch data" -ForegroundColor Green
                } catch {
                    Write-Host "  ⚠ Could not retrieve 7-Zip patch data: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        } else {
            $verifyJob = $jobs | Where-Object { $_.name -eq "verify_patch_success" -and $_.status -eq "success" }
            if ($verifyJob) {
                try {
                    $artifactsUrl = "$($env:CI_API_V4_URL)/projects/$($env:CI_PROJECT_ID)/jobs/$($verifyJob.id)/artifacts/artifacts/patch_verification.json"
                    $verificationJson = Invoke-RestMethod -Uri $artifactsUrl -Method Get -Headers $headers
                    $verificationData = $verificationJson
                    Write-Host "  ✓ Retrieved Oracle verification data" -ForegroundColor Green
                } catch {
                    Write-Host "  ⚠ Could not retrieve Oracle verification data: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
        
        # Try to get cleanup report artifact
        $cleanupData = $null
        $cleanupJob = $jobs | Where-Object { $_.name -eq "cleanup_oracle_homes" }
        if ($cleanupJob) {
            try {
                $artifactsUrl = "$($env:CI_API_V4_URL)/projects/$($env:CI_PROJECT_ID)/jobs/$($cleanupJob.id)/artifacts/artifacts/oracle_cleanup.json"
                $cleanupJson = Invoke-RestMethod -Uri $artifactsUrl -Method Get -Headers $headers
                $cleanupData = $cleanupJson
                Write-Host "  ✓ Retrieved cleanup data" -ForegroundColor Green
            } catch {
                Write-Host "  ⚠ Could not retrieve cleanup data: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        
        $pipelineStatuses += @{
            Server = $server
            PipelineId = $pipelineId
            PipelineUrl = $pipelineUrl
            Status = $status
            StartedAt = $startedAt
            FinishedAt = $finishedAt
            Duration = $duration
            FailedJobs = $failedJobs | ForEach-Object { @{
                Name = $_.name
                Stage = $_.stage
                FailureReason = $_.failure_reason
            }}
            Verification = $verificationData
            Cleanup = $cleanupData
        }
        
    } catch {
        Write-Host "  ✗ Failed to get status: $($_.Exception.Message)" -ForegroundColor Red
        
        $pipelineStatuses += @{
            Server = $server
            PipelineId = $pipelineId
            PipelineUrl = $pipelineUrl
            Status = "unknown"
            Error = $_.Exception.Message
        }
    }
    
    Write-Host ""
}

# Generate HTML report
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Generating Report" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$successCount = ($pipelineStatuses | Where-Object { $_.Status -eq "success" }).Count
$failedCount = ($pipelineStatuses | Where-Object { $_.Status -eq "failed" }).Count
$runningCount = ($pipelineStatuses | Where-Object { $_.Status -eq "running" -or $_.Status -eq "pending" }).Count

# More lenient status: SUCCESS if no failures and at least one success
$overallStatus = if ($failedCount -gt 0) { "FAILED" } 
                elseif ($runningCount -gt 0) { "IN PROGRESS" }
                elseif ($successCount -gt 0 -and $failedCount -eq 0) { "SUCCESS" }
                else { "PARTIAL" }

$statusColor = switch ($overallStatus) {
    "SUCCESS" { "#28a745" }
    "FAILED" { "#dc3545" }
    "IN PROGRESS" { "#ffc107" }
    default { "#6c757d" }
}

$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>$(if ($isTomcatPatching) { 'Tomcat' } elseif ($isMetabasePatching) { 'Metabase' } elseif ($isPostgreSQLPatching) { 'PostgreSQL' } elseif ($isApachePatching) { 'Apache' } elseif ($is7ZipPatching) { '7-Zip' } else { 'Oracle' }) Patch Report - Multi-Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 20px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid $statusColor; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 25px; }
        .summary { background-color: #f9f9f9; padding: 15px; border-radius: 5px; margin: 20px 0; border-left: 5px solid $statusColor; }
        .status-badge { padding: 8px 15px; border-radius: 3px; font-weight: bold; display: inline-block; color: white; background-color: $statusColor; }
        .metadata { color: #777; font-size: 0.9em; margin: 10px 0; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th { background-color: #4CAF50; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .success { color: #4CAF50; font-weight: bold; }
        .failed { color: #f44336; font-weight: bold; }
        .running { color: #2196F3; font-weight: bold; }
        .pending { color: #ff9800; font-weight: bold; }
        .tag-badge { background-color: #e3f2fd; color: #1976d2; padding: 3px 8px; border-radius: 3px; font-size: 0.85em; margin-right: 5px; display: inline-block; }
        .duration { color: #666; font-size: 0.9em; }
        .footer { margin-top: 30px; padding: 15px; background-color: #f9f9f9; border-radius: 5px; font-size: 0.9em; color: #666; }
        a { color: #1976d2; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h1>$(if ($isTomcatPatching) { 'Tomcat' } elseif ($isMetabasePatching) { 'Metabase' } elseif ($isPostgreSQLPatching) { 'PostgreSQL' } elseif ($isApachePatching) { 'Apache' } elseif ($is7ZipPatching) { '7-Zip' } else { 'Oracle' }) Patch Report - Multi-Server</h1>

        <div class="summary">
            <h2>Overall Status: <span class="status-badge">$overallStatus</span></h2>
            <div class="metadata">
                <p><strong>Server Group:</strong> $($reportData.ServerGroupTag)</p>
                <p><strong>Action:</strong> $action</p>
                <p><strong>Report Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
                <p><strong>Parent Pipeline:</strong> <a href="$($reportData.ParentPipelineUrl)">$($reportData.ParentPipelineUrl)</a></p>
            </div>
            <div style="margin-top: 15px;">
                <span class="success">✓ Success: $successCount</span> | 
                <span class="failed">✗ Failed: $failedCount</span> | 
                <span class="running">⟳ Running: $runningCount</span>
            </div>
        </div>
        
        <h2>Server Results</h2>
        <table>
            <thead>
                <tr>
                    <th>Server</th>
                    <th>Runner Tags</th>
                    <th>Status</th>
                    <th>Duration</th>
                    <th>Verification</th>
$(if (-not $isTomcatPatching -and -not $isMetabasePatching -and -not $isPostgreSQLPatching -and -not $isApachePatching -and -not $is7ZipPatching) { "                    <th>Cleanup</th>`n" } else { "" })                    <th>Failed Jobs</th>
                    <th>Pipeline</th>
                </tr>
            </thead>
            <tbody>
"@

foreach ($pipeline in $pipelineStatuses | Sort-Object Server) {
    $durationText = if ($pipeline.Duration) { 
        $ts = [TimeSpan]::FromSeconds($pipeline.Duration)
        "{0:mm}m {0:ss}s" -f $ts
    } else { 
        "-" 
    }
    
    $failedJobsText = if ($pipeline.FailedJobs -and $pipeline.FailedJobs.Count -gt 0) {
        ($pipeline.FailedJobs | ForEach-Object { "$($_.Stage): $($_.Name)" }) -join "<br/>"
    } else {
        "-"
    }
    
    # Build verification summary
    $verificationText = "-"
    if ($pipeline.Verification) {
        $v = $pipeline.Verification
        
        if ($isTomcatPatching) {
            # Check if this is a "no Tomcat found" scenario
            if ($v.NoTomcatFound) {
                $verificationText = @"
<span style='background-color: #6c757d; color: white; padding: 2px 8px; border-radius: 3px; font-weight: bold; font-size: 0.85em;'>NO TOMCAT INSTALLED</span><br/>
<div style='font-size: 0.85em; margin-top: 5px; color: #666;'>
<strong>Status:</strong> No Tomcat instances found on this server<br/>
<em>Discovery Date: $($v.DiscoveryDate)</em>
</div>
"@
            } else {
                # Tomcat verification format
                $verifyStatus = $v.OverallStatus
                $verifyColor = if ($verifyStatus -eq "SUCCESS") { "#28a745" } else { "#dc3545" }
            
                $versionInfo = if ($v.Version) {
                    "<strong>Version:</strong> $($v.Version)<br/>"
                } else { "" }
                
                $packageInfo = if ($v.TomcatPackage) {
                    "<strong>Package:</strong> $($v.TomcatPackage)<br/>"
                } else { "" }
                
                $domainsInfo = if ($v.Domains) {
                    $domainCount = $v.Domains.Count
                    $runningCount = ($v.Domains | Where-Object { $_.ServiceRunning -eq $true }).Count
                    $domainDetails = ""
                    foreach ($domain in $v.Domains) {
                        $serviceIcon = if ($domain.ServiceRunning) { "&#x2713;" } else { "&#x2717;" }
                        $serviceColor = if ($domain.ServiceRunning) { "#28a745" } else { "#dc3545" }
                        $verifiedIcon = if ($domain.Verified) { "&#x2713;" } else { "&#x2717;" }
                        $verifiedColor = if ($domain.Verified) { "#28a745" } else { "#dc3545" }
                        
                        $domainDetails += "<div style='margin-left: 10px; font-size: 0.9em; padding: 3px 0;'>"
                        $domainDetails += "<strong>$($domain.Domain):</strong> "
                        $domainDetails += "<span style='color: $serviceColor;'>$serviceIcon Service</span>, "
                        $domainDetails += "<span style='color: $verifiedColor;'>$verifiedIcon Verified</span>"
                        if ($domain.Error) {
                            $domainDetails += " <span style='color: #dc3545;'>($($domain.Error))</span>"
                        }
                        $domainDetails += "</div>"
                    }
                    "<strong>Domains:</strong> $runningCount/$domainCount Running<br/>$domainDetails"
                } else { "" }
                
                $issuesInfo = if ($v.Issues -and $v.Issues.Count -gt 0) {
                    "<strong style='color: #dc3545;'>Issues:</strong> $($v.Issues.Count)<br/>"
                } else {
                    "<strong style='color: #28a745;'>&#x2713; All checks passed</strong><br/>"
                }
                
                $verificationText = @"
<span style='background-color: $verifyColor; color: white; padding: 2px 8px; border-radius: 3px; font-weight: bold; font-size: 0.85em;'>$verifyStatus</span><br/>
<div style='font-size: 0.85em; margin-top: 5px;'>
$versionInfo$packageInfo$domainsInfo$issuesInfo
<em style='color: #666;'>$($v.Timestamp)</em>
</div>
"@
            }
        } elseif ($isMetabasePatching) {
            # Check if this is a "no Metabase found" scenario
            if ($v.NoMetabaseFound) {
                $verificationText = @"
<span style='background-color: #6c757d; color: white; padding: 2px 8px; border-radius: 3px; font-weight: bold; font-size: 0.85em;'>NO METABASE INSTALLED</span><br/>
<div style='font-size: 0.85em; margin-top: 5px; color: #666;'>
<strong>Status:</strong> No Metabase instances found on this server<br/>
<em>Discovery Date: $($v.Timestamp)</em>
</div>
"@
            } else {
                # Metabase verification format - multiple instances
                $verifyStatus = $v.OverallStatus
                $verifyColor = if ($verifyStatus -eq "SUCCESS") { "#28a745" } else { "#dc3545" }
            
            $packageInfo = if ($v.MetabasePackage) {
                "<strong>Package:</strong> $($v.MetabasePackage)<br/>"
            } else { "" }
            
            $summaryInfo = "<strong>Verification Summary:</strong><br/>"
            $summaryInfo += "<div style='margin-left: 10px;'>"
            $summaryInfo += "<strong>Instances:</strong> $($v.VerificationCount) total<br/>"
            $summaryInfo += "<span style='color: #28a745;'>✓ Success: $($v.SuccessCount)</span><br/>"
            if ($v.WarningCount -gt 0) {
                $summaryInfo += "<span style='color: #ffc107;'>⚠ Warnings: $($v.WarningCount)</span><br/>"
            }
            if ($v.FailedCount -gt 0) {
                $summaryInfo += "<span style='color: #dc3545;'>✗ Failed: $($v.FailedCount)</span><br/>"
            }
            $summaryInfo += "</div>"
            
            $instanceDetails = "<strong>Instance Details:</strong><br/>"
            foreach ($inst in $v.Verifications) {
                $instColor = if ($inst.ServiceRunning -and $inst.JarExists) { "#28a745" } else { "#dc3545" }
                $instIcon = if ($inst.ServiceRunning -and $inst.JarExists) { "&#x2713;" } else { "&#x2717;" }
                
                $versionInfo = if ($inst.MetabaseVersion -and $inst.MetabaseVersion -ne "Unknown") { 
                    " <strong>v$($inst.MetabaseVersion)</strong>" 
                } else { 
                    "" 
                }
                
                $javaWarning = if (-not $inst.JavaVersionCorrect) { 
                    " <span style='color: #ffc107;'>(Java $($inst.JavaVersion))</span>" 
                } else { 
                    " (Java $($inst.JavaVersion))" 
                }
                
                $instanceDetails += "<div style='margin-left: 10px; font-size: 0.9em;'>"
                $instanceDetails += "<span style='color: $instColor;'>$instIcon <strong>$($inst.ServiceName)</strong></span>$versionInfo"
                $instanceDetails += " - JAR: $([math]::Round($inst.JarSize / 1MB, 2)) MB$javaWarning"
                
                # Add plugins/OJDBC status
                if ($inst.PluginsDeleted -eq $true) {
                    $instanceDetails += "<br/><span style='color: #28a745; margin-left: 20px; font-size: 0.85em;'>&#x2713; Plugins refreshed</span>"
                } elseif ($inst.PluginsDeleted -eq $false) {
                    $instanceDetails += "<br/><span style='color: #ffc107; margin-left: 20px; font-size: 0.85em;'>⚠ Plugins not refreshed (locked files)</span>"
                }
                
                if ($inst.OJDBCDeployed -eq $true) {
                    $instanceDetails += "<span style='color: #28a745; margin-left: 10px; font-size: 0.85em;'>&#x2713; OJDBC deployed</span>"
                } elseif ($inst.OJDBCDeployed -eq $false -and $inst.PluginsDeleted -eq $false) {
                    $instanceDetails += "<span style='color: #ffc107; margin-left: 10px; font-size: 0.85em;'>⚠ OJDBC skipped</span>"
                }
                
                if ($inst.Issues.Count -gt 0) {
                    $instanceDetails += "<br/><span style='color: #ffc107; margin-left: 20px; font-size: 0.85em;'>Issues: $($inst.Issues -join ', ')</span>"
                }
                $instanceDetails += "</div>"
            }
            
            $verificationText = @"
<span style='background-color: $verifyColor; color: white; padding: 2px 8px; border-radius: 3px; font-weight: bold; font-size: 0.85em;'>$verifyStatus</span><br/>
<div style='font-size: 0.85em; margin-top: 5px;'>
$packageInfo$summaryInfo<br/>$instanceDetails
<em style='color: #666;'>$($v.Timestamp)</em>
</div>
"@
            }
        } elseif ($isPostgreSQLPatching) {
            # Check if this is a "no PostgreSQL found" scenario
            if ($v.NoPostgreSQLFound) {
                $verificationText = @"
<span style='background-color: #6c757d; color: white; padding: 2px 8px; border-radius: 3px; font-weight: bold; font-size: 0.85em;'>NO POSTGRESQL INSTALLED</span><br/>
<div style='font-size: 0.85em; margin-top: 5px; color: #666;'>
<strong>Status:</strong> No PostgreSQL instances found on this server<br/>
<em>Discovery Date: $($v.DiscoveryDate)</em>
</div>
"@
            } else {
                # PostgreSQL verification format with before/after comparison
                $verifyStatus = $v.OverallStatus
                $verifyColor = if ($verifyStatus -eq "SUCCESS") { "#28a745" } else { "#dc3545" }
                
                $packageInfo = if ($v.Package) {
                    "<strong>Package:</strong> $($v.Package)<br/>"
                } else { "" }
                
                # Build instance details with before/after version comparison
                $instanceDetails = ""
                if ($v.Verifications) {
                    foreach ($inst in $v.Verifications) {
                        # Service running status
                        $serviceStatusIcon = if ($inst.ServiceRunning) { "&#x2713;" } else { "&#x2717;" }
                        $serviceStatusColor = if ($inst.ServiceRunning) { "#28a745" } else { "#dc3545" }
                        $serviceStatusText = if ($inst.ServiceRunning) { "Running" } else { "Stopped" }
                        
                        # Version upgrade display
                        $versionDisplay = ""
                        if ($inst.PreviousVersion -and $inst.PreviousVersion -ne "Unknown" -and $inst.ActualVersion -and $inst.ActualVersion -ne "Unknown") {
                            # Show before → after
                            $versionDisplay = "<strong>$($inst.PreviousVersion)</strong> <span style='color: #17a2b8;'>&#x2192;</span> <strong style='color: #28a745;'>$($inst.ActualVersion)</strong>"
                        } elseif ($inst.ActualVersion -and $inst.ActualVersion -ne "Unknown") {
                            # Only show current version
                            $versionDisplay = "<strong>$($inst.ActualVersion)</strong>"
                        }
                        
                        $instanceDetails += "<div style='margin: 8px 0; padding: 8px; background-color: #f8f9fa; border-left: 3px solid $serviceStatusColor;'>"
                        
                        # Service name and status on first line
                        $instanceDetails += "<div style='font-size: 0.95em;'>"
                        $instanceDetails += "<strong>Service:</strong> $($inst.ServiceName) "
                        $instanceDetails += "<span style='color: $serviceStatusColor;'>$serviceStatusIcon $serviceStatusText</span>"
                        $instanceDetails += "</div>"
                        
                        # Version information on second line
                        if ($versionDisplay) {
                            $instanceDetails += "<div style='font-size: 0.9em; margin-top: 4px;'>"
                            $instanceDetails += "<strong>Version:</strong> $versionDisplay"
                            $instanceDetails += "</div>"
                        }
                        
                        # Optional: PostgreSQL Home
                        if ($inst.PostgreSQLHome) {
                            $instanceDetails += "<div style='font-size: 0.85em; margin-top: 3px; color: #666;'>"
                            $instanceDetails += "<strong>Home:</strong> $($inst.PostgreSQLHome)"
                            $instanceDetails += "</div>"
                        }
                        
                        # Optional: Data Directory
                        if ($inst.DataDirectory) {
                            $instanceDetails += "<div style='font-size: 0.85em; margin-top: 2px; color: #666;'>"
                            $instanceDetails += "<strong>Data:</strong> $($inst.DataDirectory)"
                            $instanceDetails += "</div>"
                        }
                        
                        # Issues if any
                        if ($inst.Issues -and $inst.Issues.Count -gt 0) {
                            $instanceDetails += "<div style='color: #dc3545; margin-top: 4px; font-size: 0.85em;'>"
                            $instanceDetails += "<strong>Issues:</strong> $($inst.Issues -join ', ')"
                            $instanceDetails += "</div>"
                        }
                        
                        $instanceDetails += "</div>"
                    }
                }
                
                # Add skipped instances if any
                $skippedDetails = ""
                if ($v.SkippedInstances -and $v.SkippedInstances.Count -gt 0) {
                    $skippedDetails = "<div style='margin-top: 12px; padding: 8px; background-color: #fff3cd; border-left: 3px solid #ffc107;'>"
                    $skippedDetails += "<div style='font-size: 0.95em; color: #856404;'>"
                    $skippedDetails += "<strong>⚠ Skipped Instances ($($v.SkippedInstances.Count)):</strong>"
                    $skippedDetails += "</div>"
                    
                    foreach ($skipped in $v.SkippedInstances) {
                        $skippedDetails += "<div style='margin-top: 6px; margin-left: 10px; font-size: 0.9em; color: #856404;'>"
                        $skippedDetails += "<strong>$($skipped.ServiceName)</strong> - Version: <strong>$($skipped.CurrentVersion)</strong>"
                        $skippedDetails += "<br/><span style='font-size: 0.85em;'>Reason: $($skipped.Reason) (Major version $($skipped.MajorVersion) not compatible with package)</span>"
                        $skippedDetails += "</div>"
                    }
                    
                    $skippedDetails += "</div>"
                }

                $verificationText = @"
<span style='background-color: $verifyColor; color: white; padding: 2px 8px; border-radius: 3px; font-weight: bold; font-size: 0.85em;'>$verifyStatus</span><br/>
<div style='font-size: 0.85em; margin-top: 8px;'>
$packageInfo
$instanceDetails
$skippedDetails
$issuesInfo
<em style='color: #666;'>Verified: $($v.Timestamp)</em>
</div>
"@
            }
        } elseif ($isApachePatching) {
            if ($v.VerificationSkipped) {
                $verificationText = @"
<span style='background-color: #6c757d; color: white; padding: 2px 8px; border-radius: 3px; font-weight: bold; font-size: 0.85em;'>NO APACHE INSTALLED</span><br/>
<div style='font-size: 0.85em; margin-top: 5px; color: #666;'>
<strong>Status:</strong> No Apache instances found on this server<br/>
<em>Discovery Date: $($v.Timestamp)</em>
</div>
"@
            } else {
                $verifyStatus = if ($v.VerificationPassed) { "SUCCESS" } else { "FAILED" }
                $verifyColor = if ($v.VerificationPassed) { "#28a745" } else { "#dc3545" }
                
                $instanceDetails = ""
                if ($v.Results) {
                    foreach ($inst in $v.Results) {
                        $serviceStatusIcon = if ($inst.IsRunning) { "&#x2713;" } else { "&#x2717;" }
                        $serviceStatusColor = if ($inst.IsRunning) { "#28a745" } else { "#dc3545" }
                        $serviceStatusText = if ($inst.IsRunning) { "Running" } else { "Stopped" }
                        
                        $instanceDetails += "<div style='margin: 8px 0; padding: 8px; background-color: #f8f9fa; border-left: 3px solid $serviceStatusColor;'>"
                        $instanceDetails += "<div style='font-size: 0.95em;'>"
                        $instanceDetails += "<strong>Service:</strong> $($inst.ServiceName) "
                        $instanceDetails += "<span style='color: $serviceStatusColor;'>$serviceStatusIcon $serviceStatusText</span>"
                        $instanceDetails += "</div>"
                        
                        if ($inst.Version -and $inst.Version -ne "Unknown") {
                            $instanceDetails += "<div style='font-size: 0.9em; margin-top: 4px;'>"
                            $instanceDetails += "<strong>Version:</strong> $($inst.Version)"
                            $instanceDetails += "</div>"
                        }
                        $instanceDetails += "</div>"
                    }
                }
                
                $verificationText = @"
<span style='background-color: $verifyColor; color: white; padding: 2px 8px; border-radius: 3px; font-weight: bold; font-size: 0.85em;'>$verifyStatus</span><br/>
<div style='font-size: 0.85em; margin-top: 5px;'>
$instanceDetails
<em style='color: #666;'>$($v.Timestamp)</em>
</div>
"@
            }
        } elseif ($is7ZipPatching) {
            # 7-Zip patch verification block
            if ($v) {
                $verifyStatus = "SUCCESS"
                $verifyColor = "#28a745"
                $versionInfo = "<strong>Version:</strong> $($v.Version)<br/>"
                $pathInfo = "<strong>Location:</strong> $($v.Path)<br/>"
                
                $verificationText = @"
<span style='background-color: $verifyColor; color: white; padding: 2px 8px; border-radius: 3px; font-weight: bold; font-size: 0.85em;'>$verifyStatus</span><br/>
<div style='font-size: 0.85em; margin-top: 5px;'>
$versionInfo
$pathInfo
<em style='color: #666;'>$($v.Timestamp)</em>
</div>
"@
            }
        } else {
            # Oracle verification format
            $verifyStatus = $v.OverallStatus
            $verifyColor = if ($verifyStatus -eq "PASS") { "#28a745" } else { "#ffc107" }
        
        # Highlight version if there's a mismatch
        $versionInfo = if ($v.VersionNumbers -and $v.VersionNumbers.Count -gt 0) {
            $versionColor = if ($v.VersionMismatch) { "#ffc107" } else { "inherit" }
            $versionStyle = if ($v.VersionMismatch) { "background-color: #fff3cd; padding: 2px 4px; border-radius: 3px; font-weight: bold;" } else { "" }
            
            $versionDisplay = if ($v.VersionMismatch -and $v.ExpectedPackVersion) {
                "Expected: $($v.ExpectedPackVersion) | Actual: $($v.VersionNumbers -join ', ')"
            } else {
                $v.VersionNumbers -join ', '
            }
            
            "<strong>Version:</strong> <span style='$versionStyle color: $versionColor;'>$versionDisplay</span><br/>"
        } else { "" }
        
        $appVersionInfo = if ($v.ApplicationVersion) {
            "<strong>App Version:</strong> $($v.ApplicationVersion)<br/>"
        } else { "" }
        
        $invalidObjectsInfo = "<strong>Invalid Objects:</strong> $($v.InvalidObjectsCount)<br/>"
        
        $issuesInfo = if ($v.RegistryIssues -and $v.RegistryIssues.Count -gt 0) {
            "<strong style='color: #dc3545;'>Issues:</strong> $($v.RegistryIssues.Count)<br/>"
        } else {
            "<strong style='color: #28a745;'>Components:</strong> All VALID<br/>"
        }
        
        $verificationText = @"
<span style='background-color: $verifyColor; color: white; padding: 2px 8px; border-radius: 3px; font-weight: bold; font-size: 0.85em;'>$verifyStatus</span><br/>
<div style='font-size: 0.85em; margin-top: 5px;'>
$versionInfo$appVersionInfo$invalidObjectsInfo$issuesInfo
<em style='color: #666;'>$($v.Timestamp)</em>
</div>
"@
        }
    }
    
    # Build cleanup summary
    $cleanupText = "-"
    if ($pipeline.Cleanup) {
        $c = $pipeline.Cleanup
        $totalHomes = $c.TotalUnusedHomes
        
        if ($totalHomes -eq 0) {
            $cleanupText = "<span style='color: #28a745; font-size: 0.85em;'>✓ No unused homes</span>"
        } else {
            $successCount = $c.SuccessCount
            $warningCount = $c.WarningCount
            $failedCount = $c.FailedCount
            $skippedCount = $c.SkippedCount
            
            $statusText = if ($failedCount -gt 0) { 
                "<span style='background-color: #dc3545; color: white; padding: 2px 8px; border-radius: 3px; font-weight: bold; font-size: 0.85em;'>PARTIAL</span>" 
            } elseif ($warningCount -gt 0) { 
                "<span style='background-color: #ffc107; color: #333; padding: 2px 8px; border-radius: 3px; font-weight: bold; font-size: 0.85em;'>WARNING</span>" 
            } else { 
                "<span style='background-color: #28a745; color: white; padding: 2px 8px; border-radius: 3px; font-weight: bold; font-size: 0.85em;'>SUCCESS</span>" 
            }
            
            $cleanupText = @"
$statusText<br/>
<div style='font-size: 0.85em; margin-top: 5px;'>
<strong>Unused Homes:</strong> $totalHomes<br/>
<span style='color: #28a745;'>✓ Success: $successCount</span><br/>
<span style='color: #ffc107;'>⚠ Warning: $warningCount</span><br/>
<span style='color: #dc3545;'>✗ Failed: $failedCount</span><br/>
<span style='color: #6c757d;'>⊘ Skipped: $skippedCount</span>
</div>
"@
        }
    }
    
    # Get other tags for this server from the triggered pipelines data
    $serverData = $reportData.TriggeredPipelines | Where-Object { $_.Server -eq $pipeline.Server }
    $otherTagsText = if ($serverData.OtherTags -and $serverData.OtherTags.Count -gt 0) {
        ($serverData.OtherTags | ForEach-Object { "<span class='tag-badge'>$_</span>" }) -join " "
    } else {
        "--"
    }
    
    # Display hostname if available, otherwise show runner-id
    $displayName = if ($serverData.ServerHostname) { $serverData.ServerHostname } else { $pipeline.Server }

    $cleanupColumn = if ($isTomcatPatching -or $isMetabasePatching -or $isPostgreSQLPatching -or $isApachePatching) { "" } else { "                    <td>$cleanupText</td>`n" }

    # Simplified status badge without extra class complexity
    $statusColorMap = @{
        "success" = "#4CAF50"
        "failed" = "#f44336"
        "running" = "#2196F3"
        "pending" = "#ff9800"
        "unknown" = "#777"
    }
    $statusBadgeColor = $statusColorMap[$pipeline.Status.ToLower()]
    if (-not $statusBadgeColor) { $statusBadgeColor = "#777" }
    
    $htmlReport += @"
                <tr>
                    <td><strong>$displayName</strong></td>
                    <td>$otherTagsText</td>
                    <td><span style='background-color: $statusBadgeColor; color: white; padding: 4px 12px; border-radius: 3px; font-weight: bold; font-size: 0.9em;'>$($pipeline.Status.ToUpper())</span></td>
                    <td class="duration">$durationText</td>
                    <td>$verificationText</td>
$cleanupColumn                    <td>$failedJobsText</td>
                    <td><a href="$($pipeline.PipelineUrl)" target="_blank">View Pipeline →</a></td>
                </tr>
"@
}

$htmlReport += @"
            </tbody>
        </table>
        
        <div class="footer">
            <strong>Trigger Time:</strong> $($reportData.TriggerTime)<br>
            <strong>Total Servers:</strong> $($pipelineStatuses.Count)<br>
            <strong>Report Wait Time:</strong> $([math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)) minutes<br>
            <strong>Parent Pipeline:</strong> <a href="$($reportData.ParentPipelineUrl)" target="_blank">$($reportData.ParentPipelineId)</a>
        </div>
    </div>
</body>
</html>
"@

# Save report to file
$htmlReportPath = Join-Path (Split-Path $reportFile -Parent) "pipeline_report.html"
$htmlReport | Set-Content -Path $htmlReportPath -Encoding UTF8
Write-Host "✓ Report saved to: $htmlReportPath" -ForegroundColor Green

# Send email if configured
if ($sendEmail) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Sending Email Report" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan 
    Write-Host ""

    try {
        $patchType = if ($isTomcatPatching) { "Tomcat" } elseif ($isMetabasePatching) { "Metabase" } elseif ($isPostgreSQLPatching) { "PostgreSQL" } elseif ($isApachePatching) { "Apache"  } elseif ($is7ZipPatching) { "7-Zip" } else { "Oracle" }
        $totalServers = $pipelineStatuses.Count
        $subject = "[$($reportData.ServerGroupTag)] $patchType Patch Report - $overallStatus - $successCount/$totalServers servers"
        $recipients = $reportEmailTo -split ',' | ForEach-Object { $_.Trim() }
        
        Write-Host "From: $reportEmailFrom" -ForegroundColor Gray
        Write-Host "To: $($recipients -join ', ')" -ForegroundColor Gray
        Write-Host "Subject: $subject" -ForegroundColor Gray
        Write-Host "SMTP Server: $smtpServer" -ForegroundColor Gray
        Write-Host ""
        
        Send-MailMessage `
            -From $reportEmailFrom `
            -To $recipients `
            -Subject $subject `
            -Body $htmlReport `
            -BodyAsHtml `
            -SmtpServer $smtpServer `
            -Priority $(if ($failedCount -gt 0) { "High" } else { "Normal" })
        
        Write-Host "✓ Email report sent successfully" -ForegroundColor Green
        
    } catch {
        Write-Host "✗ Failed to send email: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Report is still available at: $htmlReportPath" -ForegroundColor Yellow
    }
} else {
    Write-Host "Email sending skipped - REPORT_EMAIL_TO not configured" -ForegroundColor Yellow
    Write-Host "Report is available at: $htmlReportPath" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Report Generation Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

exit 0
