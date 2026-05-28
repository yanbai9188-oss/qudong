# YanbaiDriverWorker — runs as SYSTEM via scheduled task registered at install time.
# Polls %ProgramData%\Yanbai_Driver\queue\ for job JSON files, installs the requested
# drivers, then writes a result JSON to the results\ directory.
# The GUI (non-admin) submits jobs and polls results — no UAC prompt during normal use.

param([int]$IdleTimeoutSeconds = 3600)  # Default: idle 60 minutes before exiting

# Derive appRoot dynamically from this script's location: lib\ -> parent = appRoot
$appRoot    = Split-Path $PSScriptRoot -Parent
$svcDir     = "$env:ProgramData\Yanbai_Driver"
$queueDir   = Join-Path $svcDir 'queue'
$resultsDir = Join-Path $svcDir 'results'
$logsDir    = Join-Path $svcDir 'logs'

foreach ($d in @($queueDir, $resultsDir, $logsDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

function Write-SvcLog {
    param([string]$Msg)
    try {
        $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Msg
        Add-Content -Path (Join-Path $logsDir 'service.log') -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

Write-SvcLog 'YanbaiDriverWorker starting'

# Load the driver engine (all lib files except GUI modules)
try {
    . (Join-Path $appRoot 'engine\Initialize-Engine.ps1') -AppRoot $appRoot
    Write-SvcLog 'Engine loaded OK'
} catch {
    Write-SvcLog ("Engine load FAILED: {0}" -f $_.Exception.Message)
    exit 1
}

# ── Helpers ─────────────────────────────────────────────────────────────────

function Set-JobStatus {
    param([string]$JobId, [string]$Status, [string]$Message, [int]$Progress = 0)
    $f = Join-Path $resultsDir "$JobId.result.json"
    try {
        [ordered]@{ jobId = $JobId; status = $Status; message = $Message; progress = $Progress } |
            ConvertTo-Json | Set-Content $f -Encoding UTF8
    } catch {}
}

# Reconstruct a minimal PSCustomObject from the serialised job item.
function ConvertFrom-JobItem {
    param($ji)
    $dev = [PSCustomObject]@{
        InstanceId   = [string]$ji.deviceInstanceId
        FriendlyName = [string]$ji.deviceFriendlyName
        HardwareIds  = @(if ($ji.deviceHardwareIds) { [string[]]$ji.deviceHardwareIds } else { @() })
        Status       = 'Problem'
        IsProblem    = $true
    }
    $pkg = $null
    if ($ji.packageId) {
        $pkg = [PSCustomObject]@{
            PackageId      = [string]$ji.packageId
            Id             = [string]$ji.packageId
            Title          = if ($ji.packageTitle)       { [string]$ji.packageTitle       } else { [string]$ji.packageId }
            Url            = if ($ji.packageUrl)         { [string]$ji.packageUrl         } else { $null }
            LocalPath      = if ($ji.packageLocalPath)   { [string]$ji.packageLocalPath   } else { $null }
            Sha256         = if ($ji.packageSha256)      { [string]$ji.packageSha256      } else { $null }
            InstallType    = if ($ji.installType)        { [string]$ji.installType        } else { 'inf'  }
            RebootRequired = [bool]$ji.packageRebootRequired
            Sources        = if ($ji.packageSources)     { @($ji.packageSources)          } else { @() }
        }
    }
    return [PSCustomObject]@{
        Device  = $dev
        Package = $pkg
        Action  = [string]$ji.action
        Score   = 80
    }
}

# ── Process one job file ─────────────────────────────────────────────────────

function Process-Job {
    param([string]$JobFile)

    # Read and parse — bail on any error
    try { $raw = Get-Content $JobFile -Raw -Encoding UTF8 } catch { return }
    try { $job = $raw | ConvertFrom-Json } catch {
        Write-SvcLog ("JSON parse error in {0}: {1}" -f (Split-Path $JobFile -Leaf), $_.Exception.Message)
        Remove-Item $JobFile -Force -ErrorAction SilentlyContinue
        return
    }

    $jobId = [string]$job.jobId
    if (-not $jobId) { Remove-Item $JobFile -Force -ErrorAction SilentlyContinue; return }

    Write-SvcLog ("Job {0}: type={1} items={2}" -f $jobId, $job.type, @($job.items).Count)
    Set-JobStatus -JobId $jobId -Status 'running' -Message '正在准备...' -Progress 3

    # Move job file to processing dir BEFORE we start (not delete — if we crash we can inspect it).
    # We only remove it after a terminal result has been written so no job is silently lost.
    $processingDir = Join-Path $queueDir 'processing'
    if (-not (Test-Path $processingDir)) { New-Item -ItemType Directory -Force -Path $processingDir | Out-Null }
    $processingFile = Join-Path $processingDir (Split-Path $JobFile -Leaf)
    try { Move-Item $JobFile $processingFile -Force -ErrorAction Stop } catch {
        # Move failed — write a failure result immediately and do NOT delete the queue file.
        # This prevents silent job loss; the next poll cycle will see the original file still there.
        Write-SvcLog ("Move to processing\ failed for job {0}: {1}" -f $jobId, $_.Exception.Message)
        Set-JobStatus -JobId $jobId -Status 'failed' -Message ('内部错误：任务文件移动失败: ' + $_.Exception.Message) -Progress 0
        return
        $processingFile = $null  # unreachable; kept for symmetry
    }

    try {
        $items = @($job.items | ForEach-Object { ConvertFrom-JobItem $_ })
        if ($items.Count -eq 0) { throw '任务没有驱动项' }

        $backup         = if ($job.options -and $null -ne $job.options.backupFirst)        { [bool]$job.options.backupFirst        } else { $false }
        $rollbackOnErr  = if ($job.options -and $null -ne $job.options.rollbackOnError)   { [bool]$job.options.rollbackOnError    } else { $true  }
        $verifyInstall  = if ($job.options -and $null -ne $job.options.verifyInstall)     { [bool]$job.options.verifyInstall      } else { $true  }
        $total  = $items.Count
        $idx    = 0

        $onLog  = { param($m) Write-SvcLog ("  {0}" -f [string]$m) }.GetNewClosure()

        $allResults   = New-Object System.Collections.ArrayList
        $rebootNeeded = $false

        foreach ($item in $items) {
            $idx++
            $basePct = [int](($idx - 1) / $total * 85) + 5
            Set-JobStatus -JobId $jobId -Status 'running' `
                -Message ("正在处理: {0} ({1}/{2})" -f $item.Device.FriendlyName, $idx, $total) `
                -Progress $basePct

            # Wire per-item download/install progress back into Set-JobStatus so the GUI
            # progress bar moves during long downloads rather than appearing stuck.
            $capturedJobId   = $jobId
            $capturedBase    = $basePct
            $capturedTotal   = $total
            $capturedIdx     = $idx
            $capturedName    = [string]$item.Device.FriendlyName
            $itemProgressCb  = {
                param($pPct, $pName)
                # Map inner 0-100% to a slice of the global job progress range
                $sliceWidth = [int](85 / $capturedTotal)
                $mapped = $capturedBase + [int]($pPct / 100 * $sliceWidth)
                $mapped = [Math]::Min($mapped, $capturedBase + $sliceWidth)
                $msg = if ($pName) { [string]$pName } else { "正在安装: $capturedName" }
                Set-JobStatus -JobId $capturedJobId -Status 'running' -Message $msg -Progress $mapped
            }.GetNewClosure()

            try {
                if ($backup) {
                    try { Backup-DeviceDriver -InstanceId $item.Device.InstanceId -FriendlyName $item.Device.FriendlyName -OnLog $onLog | Out-Null } catch {
                        Write-SvcLog ("  Backup failed for {0}: {1}" -f $item.Device.FriendlyName, $_.Exception.Message)
                    }
                }
                Invoke-FixPlanItemInstall -Item $item -OnLog $onLog -OnProgress $itemProgressCb
                if ($item.Package -and $item.Package.RebootRequired) { $rebootNeeded = $true }
                [void]$allResults.Add([ordered]@{
                    device  = [string]$item.Device.FriendlyName
                    success = $true
                    action  = [string]$item.Action
                    pkgId   = if ($item.Package) { [string]$item.Package.PackageId } else { '' }
                    error   = $null
                })
                Write-SvcLog ("  [OK] {0}" -f $item.Device.FriendlyName)
            } catch {
                $errMsg = $_.Exception.Message
                Write-SvcLog ("  [FAIL] {0}: {1}" -f $item.Device.FriendlyName, $errMsg)
                [void]$allResults.Add([ordered]@{
                    device  = [string]$item.Device.FriendlyName
                    success = $false
                    action  = [string]$item.Action
                    pkgId   = if ($item.Package) { [string]$item.Package.PackageId } else { '' }
                    error   = $errMsg
                })
            }
        }

        $ok     = @($allResults | Where-Object { $_.success }).Count
        $fail   = @($allResults | Where-Object { -not $_.success }).Count
        $msg    = if ($fail -eq 0) { "成功安装 $ok 个驱动" } else { "成功 $ok · 失败 $fail" }
        $status = if ($fail -eq 0) { 'success' } elseif ($ok -eq 0) { 'failed' } else { 'partial' }

        [ordered]@{
            jobId        = $jobId
            status       = $status
            message      = $msg
            progress     = 100
            results      = @($allResults.ToArray())
            rebootNeeded = $rebootNeeded
            rolledBack   = $false   # ServiceWorker does not implement rollback yet; always false
            txId         = ''
            completedAt  = (Get-Date -Format 'o')
        } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $resultsDir "$jobId.result.json") -Encoding UTF8

        Write-SvcLog ("Job {0} DONE: {1}" -f $jobId, $msg)

    } catch {
        $errMsg = $_.Exception.Message
        Write-SvcLog ("Job {0} ERROR: {1}" -f $jobId, $errMsg)
        [ordered]@{
            jobId       = $jobId
            status      = 'failed'
            message     = $errMsg
            progress    = 0
            completedAt = (Get-Date -Format 'o')
        } | ConvertTo-Json | Set-Content (Join-Path $resultsDir "$jobId.result.json") -Encoding UTF8
    } finally {
        # Clean up the in-progress copy now that a terminal result file exists
        if ($processingFile -and (Test-Path $processingFile)) {
            Remove-Item $processingFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# ── Main poll loop ───────────────────────────────────────────────────────────

Write-SvcLog ("Poll loop start (idle-timeout={0}s)" -f $IdleTimeoutSeconds)
$lastActivity = Get-Date

while ((Get-Date) -lt $lastActivity.AddSeconds($IdleTimeoutSeconds)) {
    $jobs = @(Get-ChildItem $queueDir -Filter '*.job.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    if ($jobs.Count -gt 0) {
        $lastActivity = Get-Date
        foreach ($j in $jobs) { Process-Job $j.FullName }
    } else {
        Start-Sleep -Milliseconds 1500
    }
}

Write-SvcLog 'ServiceWorker idle-timeout reached, exiting'
