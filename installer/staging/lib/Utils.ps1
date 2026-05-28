# Shared utilities

function Get-AppRoot {
    if ($global:DriverBoosterAppRoot) { return $global:DriverBoosterAppRoot }
    if ($script:AppRoot) { return $script:AppRoot }

    $candidates = @()
    if ($PSScriptRoot) { $candidates += $PSScriptRoot }
    try {
        $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($exePath) { $candidates += (Split-Path $exePath -Parent) }
    } catch { }

    foreach ($root in ($candidates | Select-Object -Unique)) {
        if ($root -and (Test-Path (Join-Path $root 'lib'))) {
            $global:DriverBoosterAppRoot = $root
            return $global:DriverBoosterAppRoot
        }
    }
    throw 'AppRoot not initialized. Load engine/Initialize-Engine.ps1 first.'
}

function Test-CIODIYPathWritable {
    param([Parameter(Mandatory)][string]$Directory)
    try {
        if (-not (Test-Path $Directory)) {
            New-Item -ItemType Directory -Force -Path $Directory -ErrorAction Stop | Out-Null
        }
        $testFile = Join-Path $Directory ('._write_test_{0}' -f $PID)
        Set-Content -LiteralPath $testFile -Value '1' -Encoding UTF8 -ErrorAction Stop
        Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

function Get-CIODIYUserDataRoot {
    # Always use the canonical Yanbai_Driver path.
    # The old CIODIY_DriverBooster fallback caused log-path mismatch: the app
    # wrote to the legacy dir while Launch.vbs polled Yanbai_Driver, so the
    # launcher always believed the process had not started.
    $primary = Join-Path $env:LOCALAPPDATA 'Yanbai_Driver'
    if (-not (Test-Path $primary)) {
        New-Item -ItemType Directory -Force -Path $primary -ErrorAction SilentlyContinue | Out-Null
    }
    return $primary
}

function Get-AppDataRoot {
    if ($script:CachedDataRoot) { return $script:CachedDataRoot }

    $installRoot = Get-AppRoot
    $installCache = Join-Path $installRoot 'Cache'
    if (Test-CIODIYPathWritable -Directory $installCache) {
        $script:CachedDataRoot = $installRoot
        return $script:CachedDataRoot
    }

    $userRoot = Get-CIODIYUserDataRoot
    if (-not (Test-Path $userRoot)) {
        New-Item -ItemType Directory -Force -Path $userRoot | Out-Null
    }
    $script:CachedDataRoot = $userRoot
    return $script:CachedDataRoot
}

function Initialize-AppFolders {
    try { $root = Get-AppRoot }    catch { $root = $null }
    try { $data = Get-AppDataRoot } catch { $data = $null }

    if ($root) {
        $driversPath = Join-Path $root 'Drivers'
        if (-not (Test-Path $driversPath)) {
            try { New-Item -ItemType Directory -Force -Path $driversPath -ErrorAction Stop | Out-Null } catch { }
        }
    }

    if ($data) {
        foreach ($name in @('DriverBackup', 'Logs', 'Cache', 'Transactions')) {
            $path = Join-Path $data $name
            if (-not (Test-Path $path)) {
                try { New-Item -ItemType Directory -Force -Path $path | Out-Null } catch { }
            }
        }
    }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-IsAdmin)) {
        throw '需要管理员权限。'
    }
}

function Write-AppLog {
    param(
        [string]$Message,
        [scriptblock]$OnLog
    )
    $msg = [string]$Message
    if ($msg.Length -gt 2000) { $msg = $msg.Substring(0, 2000) + '...' }
    $line = '[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $msg
    if ($OnLog) {
        try { & $OnLog $line } catch { }
        return
    }
    try {
        if (-not $script:CachedLogDir) {
            $script:CachedLogDir = Join-Path (Get-AppDataRoot) 'Logs'
        }
        if (-not (Test-Path $script:CachedLogDir)) {
            New-Item -ItemType Directory -Force -Path $script:CachedLogDir | Out-Null
        }
        $logFile = Join-Path $script:CachedLogDir ('session_{0:yyyyMMdd}.log' -f (Get-Date))
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

function Get-CategoryLabel {
    param([string]$Class, [string]$Category)
    if ($Category) {
        switch ($Category) {
            'chipset'   { return '芯片组' }
            'lan'       { return '有线网' }
            'wifi'      { return '无线网' }
            'bluetooth' { return '蓝牙' }
            'audio'     { return '音频' }
            'gpu'       { return '显卡' }
            'storage'   { return '存储' }
            'usb'       { return 'USB' }
            'mei'       { return 'MEI' }
            'platform'  { return '平台' }
            'serial'    { return '串口 IO' }
            'touchpad'  { return '触摸板' }
            'printer'   { return '打印机' }
            default     { return $Category }
        }
    }
    switch ($Class) {
        'MEDIA'     { return '音频' }
        'Net'       { return '网络' }
        'Bluetooth' { return '蓝牙' }
        'Display'   { return '显示' }
        'System'    { return '系统' }
        'HDC'       { return '存储' }
        'USB'       { return 'USB' }
        default     { if ($Class) { return $Class } else { return '未知' } }
    }
}

function Normalize-HardwareId {
    param([string]$Id)
    if ([string]::IsNullOrWhiteSpace($Id)) { return $null }
    return $Id.Trim().ToUpperInvariant()
}

function Test-HardwareIdMatch {
    param(
        [string[]]$DeviceIds,
        [string[]]$PatternIds
    )
    if (-not $PatternIds -or $PatternIds.Count -eq 0) { return $false }
    if (-not $DeviceIds -or $DeviceIds.Count -eq 0) { return $false }
    foreach ($pattern in $PatternIds) {
        $p = Normalize-HardwareId $pattern
        if (-not $p) { continue }
        foreach ($deviceId in $DeviceIds) {
            $d = Normalize-HardwareId $deviceId
            if (-not $d) { continue }
            if ($d -like ($p + '*') -or $d -eq $p) { return $true }
        }
    }
    return $false
}

function Get-FileSha256 {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Compare-DriverVersion {
    param(
        [string]$Installed,
        [string]$Available
    )
    if ([string]::IsNullOrWhiteSpace($Available)) { return 0 }
    if ([string]::IsNullOrWhiteSpace($Installed)) { return -1 }
    try {
        $aText = ($Installed -replace '[^\d\.]', '').Trim('.')
        $bText = ($Available -replace '[^\d\.]', '').Trim('.')
        if (-not $aText) { return -1 }
        if (-not $bText) { return 0 }
        $a = [version]$aText
        $b = [version]$bText
        return [Math]::Sign($a.CompareTo($b))
    } catch {
        return 0
    }
}
function Save-RemoteFileSingle {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Path,
        [scriptblock]$OnProgress,
        [int]$TimeoutSec = 7200
    )

    if (-not $OnProgress) {
        Invoke-WebRequest -Uri $Uri -OutFile $Path -UseBasicParsing -TimeoutSec $TimeoutSec
        return
    }

    $wc = New-Object System.Net.WebClient
    $eventSub = Register-ObjectEvent -InputObject $wc -EventName DownloadProgressChanged -Action {
        $pct = $Event.SourceEventArgs.ProgressPercentage
        $mb = [math]::Round($Event.SourceEventArgs.BytesReceived / 1MB, 1)
        $totalMb = if ($Event.SourceEventArgs.TotalBytesToReceive -gt 0) {
            [math]::Round($Event.SourceEventArgs.TotalBytesToReceive / 1MB, 1)
        } else { 0 }
        if ($Event.MessageData) {
            & $Event.MessageData $pct $mb $totalMb
        }
    } -MessageData $OnProgress

    try {
        $wc.DownloadFile($Uri, $Path)
    } finally {
        if ($eventSub) { Unregister-Event -SourceIdentifier $eventSub.Name -ErrorAction SilentlyContinue }
        if ($eventSub) { Remove-Job -Job $eventSub -Force -ErrorAction SilentlyContinue }
        $wc.Dispose()
    }
}

function Save-RemoteFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Path,
        [scriptblock]$OnProgress,
        [int]$TimeoutSec = 7200,
        [int]$Threads = 8,
        [long]$MinSizeForMultithread = 2MB
    )

    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    # Probe with HEAD to learn size + range support
    $totalBytes = -1L
    $supportsRange = $false
    $finalUri = $Uri
    try {
        # Use HttpClient (not HttpWebRequest, simpler redirect handling)
        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.AllowAutoRedirect = $true
        $client = New-Object System.Net.Http.HttpClient $handler
        $client.Timeout = [TimeSpan]::FromSeconds([Math]::Min($TimeoutSec, 60))
        $client.DefaultRequestHeaders.UserAgent.ParseAdd('Yanbai-Driver/1.8.9') | Out-Null
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Head, $Uri)
        $resp = $client.SendAsync($req).GetAwaiter().GetResult()
        if ($resp.IsSuccessStatusCode) {
            if ($resp.Content.Headers.ContentLength.HasValue) { $totalBytes = [long]$resp.Content.Headers.ContentLength.Value }
            $ar = $null
            if ($resp.Headers.AcceptRanges) { $ar = ($resp.Headers.AcceptRanges -join ',') }
            if ($ar -match 'bytes') { $supportsRange = $true }
            if ($resp.RequestMessage -and $resp.RequestMessage.RequestUri) { $finalUri = [string]$resp.RequestMessage.RequestUri }
        }
        $resp.Dispose(); $req.Dispose(); $client.Dispose(); $handler.Dispose()
    } catch {
        # If HEAD fails, fall back to single-thread
    }

    # Fall back to single-thread if too small, no range, or only 1 thread requested
    if ($Threads -le 1 -or -not $supportsRange -or $totalBytes -lt $MinSizeForMultithread -or $totalBytes -le 0) {
        Save-RemoteFileSingle -Uri $Uri -Path $Path -OnProgress $OnProgress -TimeoutSec $TimeoutSec
        return
    }

    # Cap threads to a reasonable count given file size (1 thread per ~512KB minimum)
    $effThreads = [Math]::Min($Threads, [Math]::Max(2, [Math]::Floor($totalBytes / 512KB)))
    if ($effThreads -lt 2) {
        Save-RemoteFileSingle -Uri $Uri -Path $Path -OnProgress $OnProgress -TimeoutSec $TimeoutSec
        return
    }

    $chunkSize = [Math]::Ceiling([double]$totalBytes / $effThreads)
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("yanbai-dl-{0}-{1}" -f $PID, (Get-Random))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        $parts = @()
        for ($i = 0; $i -lt $effThreads; $i++) {
            $start = [long]($i * $chunkSize)
            $end = [long]([Math]::Min($start + $chunkSize - 1, $totalBytes - 1))
            if ($start -gt $end) { break }
            $partPath = Join-Path $tempDir ("part_{0:D3}.bin" -f $i)
            $parts += @{ Start = $start; End = $end; Path = $partPath; Index = $i }
        }

        # ConcurrentDictionary tracks bytes per part for progress
        $progressBytes = [System.Collections.Concurrent.ConcurrentDictionary[int,long]]::new()
        foreach ($p in $parts) { [void]$progressBytes.TryAdd($p.Index, 0L) }

        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $pool = [RunspaceFactory]::CreateRunspacePool(1, $parts.Count, $iss, $Host)
        $pool.Open()

        $workScript = {
            param($url, $start, $end, $path, $idx, $progressBytes)
            try {
                $req = [System.Net.HttpWebRequest]::Create($url)
                $req.Method = 'GET'
                $req.AddRange($start, $end)
                $req.UserAgent = 'Yanbai-Driver/1.8.9'
                $req.AllowAutoRedirect = $true
                $req.Timeout = 60000
                $req.ReadWriteTimeout = 300000
                $req.KeepAlive = $true
                $resp = $req.GetResponse()
                $stream = $resp.GetResponseStream()
                $fs = [System.IO.File]::Create($path)
                $buf = New-Object byte[] 81920
                $bytesInPart = 0L
                while ($true) {
                    $r = $stream.Read($buf, 0, $buf.Length)
                    if ($r -le 0) { break }
                    $fs.Write($buf, 0, $r)
                    $bytesInPart += $r
                    [void]$progressBytes.AddOrUpdate($idx, $bytesInPart, [Func[int,long,long]]{ param($k,$old) $bytesInPart })
                }
                $fs.Close()
                $stream.Close()
                $resp.Close()
                return @{ Success = $true; Index = $idx; Bytes = $bytesInPart }
            } catch {
                return @{ Success = $false; Index = $idx; Error = $_.Exception.Message }
            }
        }

        $jobs = @()
        foreach ($p in $parts) {
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($workScript)
            [void]$ps.AddArgument($finalUri)
            [void]$ps.AddArgument($p.Start)
            [void]$ps.AddArgument($p.End)
            [void]$ps.AddArgument($p.Path)
            [void]$ps.AddArgument($p.Index)
            [void]$ps.AddArgument($progressBytes)
            $jobs += @{ PS = $ps; Async = $ps.BeginInvoke() }
        }

        $startTime = Get-Date
        $deadline = $startTime.AddSeconds($TimeoutSec)
        $lastReport = [DateTime]::MinValue
        while ($true) {
            $allDone = $true
            foreach ($j in $jobs) { if (-not $j.Async.IsCompleted) { $allDone = $false; break } }
            if ($allDone) { break }
            if ((Get-Date) -gt $deadline) {
                throw "Multithreaded download timeout after $TimeoutSec seconds"
            }

            if ($OnProgress -and ((Get-Date) - $lastReport).TotalMilliseconds -gt 250) {
                $sum = 0L
                foreach ($v in $progressBytes.Values) { $sum += $v }
                $pct = if ($totalBytes -gt 0) { [int](($sum / [double]$totalBytes) * 100) } else { 0 }
                $mb = [math]::Round($sum / 1MB, 1)
                $totalMb = [math]::Round($totalBytes / 1MB, 1)
                & $OnProgress $pct $mb $totalMb
                $lastReport = Get-Date
            }
            Start-Sleep -Milliseconds 150
        }

        # Collect results, propagate errors
        $errors = @()
        foreach ($j in $jobs) {
            $r = $j.PS.EndInvoke($j.Async)
            $j.PS.Dispose()
            $first = if ($r) { @($r)[0] } else { $null }
            if (-not $first -or -not $first.Success) {
                $errors += [string]($first.Error)
            }
        }
        $pool.Close(); $pool.Dispose()

        if ($errors.Count -gt 0) {
            throw "Multithreaded download failed: $($errors -join '; ')"
        }

        # Merge parts in order
        $outFs = [System.IO.File]::Create($Path)
        try {
            foreach ($p in ($parts | Sort-Object Index)) {
                if (-not (Test-Path $p.Path)) { throw "Missing chunk: $($p.Path)" }
                $partFs = [System.IO.File]::OpenRead($p.Path)
                try { $partFs.CopyTo($outFs) } finally { $partFs.Close() }
            }
        } finally {
            $outFs.Close()
        }

        if ($OnProgress) {
            $totalMb = [math]::Round($totalBytes / 1MB, 1)
            & $OnProgress 100 $totalMb $totalMb
        }
    } finally {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-SystemRestorePoint {
    param([string]$Description = 'CIODIY Driver Fix')

    $result = [PSCustomObject]@{
        Success = $false
        Code    = 'RESTORE_POINT_FAILED'
        Message = 'System restore point unavailable; driver backup will be used'
        Detail  = ''
    }

    try {
        $enabled = $false
        try {
            $prot = Get-CimInstance -ClassName Win32_SystemRestore -Namespace root\default -EA SilentlyContinue |
                Select-Object -First 1
            if ($prot) { $enabled = [bool]$prot.SystemRestoreEnabled }
        } catch { }

        Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue | Out-Null
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        $result.Success = $true
        $result.Code = 'OK'
        $result.Message = 'System restore point created'
        $result.Detail = $Description
        return $result
    } catch {
        $result.Detail = $_.Exception.Message
        if (-not $enabled) {
            $result.Message = 'System protection disabled; skipped restore point (backup available)'
            $result.Code = 'RESTORE_DISABLED'
        }
        return $result
    }
}
