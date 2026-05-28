# Job-queue helpers — GUI side
# The GUI (normal-user process) writes JSON job files; the SYSTEM-level scheduled task
# (YanbaiDriverWorker / ServiceWorker.ps1) picks them up, installs the drivers, and
# writes a result JSON back.  No UAC prompt after the initial install registration.

function Get-CIODIYServiceDir  { "$env:ProgramData\Yanbai_Driver" }
function Get-CIODIYQueueDir    { Join-Path (Get-CIODIYServiceDir) 'queue'   }
function Get-CIODIYResultsDir  { Join-Path (Get-CIODIYServiceDir) 'results' }

# Serialize one fix-plan item into the minimal JSON shape the ServiceWorker needs.
function ConvertTo-CIODIYJobItem {
    param($Item)
    $dev = $Item.Device
    $pkg = $Item.Package
    $ji  = [ordered]@{
        deviceInstanceId   = [string]$dev.InstanceId
        deviceFriendlyName = [string]$dev.FriendlyName
        deviceHardwareIds  = @(if ($dev.HardwareIds) { @($dev.HardwareIds | ForEach-Object { [string]$_ }) } else { @() })
        action             = [string]$Item.Action
    }
    if ($pkg) {
        $pkgId  = if ($pkg.PackageId) { $pkg.PackageId } elseif ($pkg.Id) { $pkg.Id } else { '' }
        $pkgTtl = if ($pkg.Title)     { $pkg.Title }     else { '' }
        $ji.packageId             = [string]$pkgId
        $ji.packageTitle          = [string]$pkgTtl
        $ji.packageUrl            = if ($pkg.Url)         { [string]$pkg.Url         } else { $null }
        $ji.packageLocalPath      = if ($pkg.LocalPath)   { [string]$pkg.LocalPath   } else { $null }
        $ji.packageSha256         = if ($pkg.Sha256)      { [string]$pkg.Sha256      } else { $null }
        $ji.installType           = if ($pkg.InstallType) { [string]$pkg.InstallType } else { 'inf' }
        $ji.packageRebootRequired = [bool]$pkg.RebootRequired
        # Preserve multi-source array so ServiceWorker can use Invoke-MultiSourceDriverDownload
        if ($pkg.Sources -and @($pkg.Sources).Count -gt 0) {
            $ji.packageSources = @($pkg.Sources)
        }
    }
    return $ji
}

# Submit a batch of fix items as one job; returns the jobId string.
function Submit-CIODIYDriverJob {
    param(
        [Parameter(Mandatory)][array]$FixPlan,
        [bool]$BackupFirst        = $false,
        [bool]$RollbackOnError    = $true,
        [bool]$CreateRestorePoint = $false,
        [bool]$VerifyInstall      = $true
    )
    $qDir = Get-CIODIYQueueDir
    if (-not (Test-Path $qDir)) { New-Item -ItemType Directory -Force -Path $qDir | Out-Null }

    $jobId  = [Guid]::NewGuid().ToString('N').Substring(0, 12)
    $items  = @($FixPlan | ForEach-Object { ConvertTo-CIODIYJobItem $_ })
    $job    = [ordered]@{
        jobId       = $jobId
        type        = 'fix_drivers'
        items       = $items
        options     = @{
            backupFirst         = $BackupFirst
            rollbackOnError     = $RollbackOnError
            createRestorePoint  = $CreateRestorePoint
            verifyInstall       = $VerifyInstall
        }
        requestedAt = (Get-Date -Format 'o')
        requestedBy = $env:USERNAME
    }
    $jobFile = Join-Path $qDir "$jobId.job.json"
    $job | ConvertTo-Json -Depth 8 | Set-Content $jobFile -Encoding UTF8

    # Kick the scheduled task; if it's already running it will pick up the new job on its
    # next queue poll — IgnoreNew prevents duplicate instances.
    try {
        Start-ScheduledTask -TaskName 'YanbaiDriverWorker' -ErrorAction Stop
    } catch {
        # Log failure — job file is already written so worker will still process it if task
        # starts later (e.g. after reboot). Do NOT silently swallow so caller can surface this.
        $svcDir = Get-CIODIYServiceDir
        try {
            $logLine = "[{0}] Start-ScheduledTask failed: {1}" -f (Get-Date -Format 'HH:mm:ss'), $_.Exception.Message
            Add-Content -Path (Join-Path $svcDir 'logs\queue.log') -Value $logLine -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch {}
        Write-Warning "YanbaiDriverWorker task start failed: $($_.Exception.Message)"
    }

    return $jobId
}

# Read the current status of a job (returns a PSCustomObject with .status, .progress, .message …).
function Get-CIODIYJobStatus {
    param([Parameter(Mandatory)][string]$JobId)
    $f = Join-Path (Get-CIODIYResultsDir) "$JobId.result.json"
    if (-not (Test-Path $f)) {
        return [PSCustomObject]@{ jobId = $JobId; status = 'queued'; progress = 0; message = '等待服务处理...' }
    }
    try {
        $r = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $r.status) { $r | Add-Member -NotePropertyName status -NotePropertyValue 'unknown' -Force }
        return $r
    } catch {
        return [PSCustomObject]@{ jobId = $JobId; status = 'unknown'; message = $_.Exception.Message }
    }
}

# Delete the result file once the GUI has consumed it.
function Remove-CIODIYJobResult {
    param([string]$JobId)
    $f = Join-Path (Get-CIODIYResultsDir) "$JobId.result.json"
    if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
}

# Returns $true if the YanbaiDriverWorker scheduled task is registered.
function Get-CIODIYServiceRegisteredFlag {
    return Join-Path (Get-CIODIYServiceDir) 'service_registered.flag'
}

function Test-CIODIYServiceWorkerAvailable {
    # Primary: check a marker file written by install-task.ps1 after successful registration.
    # This works in any runspace (no ScheduledTasks module dependency) and survives
    # cross-session detection reliably.
    $flag = Get-CIODIYServiceRegisteredFlag
    if (Test-Path $flag) { return $true }

    # Fallback: try Get-ScheduledTask (may not work in custom runspaces)
    try {
        $task = Get-ScheduledTask -TaskName 'YanbaiDriverWorker' -ErrorAction SilentlyContinue
        if ($task) {
            # Write the flag so future checks are fast
            try {
                $dir = Split-Path $flag -Parent
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
                [System.IO.File]::WriteAllText($flag, (Get-Date -Format 'o'))
            } catch {}
            return $true
        }
    } catch {}
    return $false
}
