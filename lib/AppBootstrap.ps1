# First-run bootstrap — sync manifest, init cache (Driver Booster-style ready-to-use)

function Get-BootstrapStatePath {
    return Join-Path (Join-Path (Get-AppDataRoot) 'Cache') 'bootstrap.json'
}

function Get-BootstrapState {
    $path = Get-BootstrapStatePath
    if (-not (Test-Path $path)) { return $null }
    try {
        return Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Set-BootstrapState {
    param(
        [string]$ManifestVersion = '',
        [bool]$OnlineSync = $false
    )
    $path = Get-BootstrapStatePath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $obj = [PSCustomObject]@{
        initialized_at   = (Get-Date -Format 'o')
        manifest_version = $ManifestVersion
        online_sync      = $OnlineSync
        app_version      = if ($script:AppVersion) { $script:AppVersion } elseif ($global:AppVersion) { $global:AppVersion } else { '2.2.2' }
    }
    ($obj | ConvertTo-Json) | Set-Content $path -Encoding UTF8
}

function Test-AppNeedsBootstrap {
    param([switch]$Force)

    if ($Force) { return $true }
    $state = Get-BootstrapState
    if (-not $state) { return $true }

    $localManifest = Get-LocalManifestPath
    if (-not $localManifest) { return $true }

    # Re-bootstrap if manifest cache older than 7 days
    if ($state.initialized_at) {
        try {
            $at = [DateTime]::Parse($state.initialized_at)
            if ((Get-Date) - $at -gt [TimeSpan]::FromDays(7)) { return $true }
        } catch { return $true }
    }
    return $false
}

function Invoke-MSCatalogLTSPreinstall {
    <#
    .SYNOPSIS
        Silently pre-install MSCatalogLTS in the background during app startup.
        This way the module is ready by the time the user clicks "fix a driver".
        Runs only once every 7 days; ignores all errors.
    #>
    param([scriptblock]$OnLog)

    # Skip if already loaded
    if (Get-Command Get-MSCatalogUpdate -ErrorAction SilentlyContinue) { return }
    if (Get-Module -ListAvailable -Name MSCatalogLTS -ErrorAction SilentlyContinue) { return }

    # Check status cache — don't retry more often than once per 7 days
    $cacheDir    = Join-Path (Get-AppDataRoot) 'Cache'
    $statusPath  = Join-Path $cacheDir 'mscataloglts_status.json'
    if (Test-Path $statusPath) {
        try {
            $st = Get-Content $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($st.timestamp) {
                $age = (Get-Date) - [DateTime]::Parse($st.timestamp)
                if ($st.status -eq 'ok'     -and $age.TotalDays -lt 7)   { return }
                if ($st.status -eq 'failed' -and $age.TotalHours -lt 24) { return }
            }
        } catch {}
    }

    # Fire-and-forget: run in a background job so startup is not delayed
    Write-AppLog 'MSCatalogLTS: 后台预安装中...' -OnLog $OnLog
    $cachePathForJob = $statusPath

    $null = Start-Job -ScriptBlock {
        param($cachePath)
        try {
            if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue | Where-Object Version -ge '2.8.5.201')) {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
            }
            Install-Module -Name MSCatalogLTS -Scope CurrentUser -Force -AllowClobber `
                -Repository PSGallery -ErrorAction Stop
            [PSCustomObject]@{ status = 'ok'; timestamp = (Get-Date -Format 'o') } |
                ConvertTo-Json | Set-Content $cachePath -Encoding UTF8
        } catch {
            $dir = Split-Path $cachePath -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
            [PSCustomObject]@{ status = 'failed'; timestamp = (Get-Date -Format 'o'); error = $_.Exception.Message } |
                ConvertTo-Json | Set-Content $cachePath -Encoding UTF8
        }
    } -ArgumentList $cachePathForJob
}

function Invoke-AppBootstrap {
    param(
        [scriptblock]$OnLog,
        [switch]$Force,
        [switch]$Background
    )

    Initialize-AppFolders

    $localPath = Get-LocalManifestPath
    if (-not $localPath) {
        throw '初始化失败: 无可用驱动清单'
    }

    $manifest = Import-DriverManifest -Path $localPath
    $online = $false
    $needsSync = Test-AppNeedsBootstrap -Force:$Force

    if ($needsSync) {
        if ($Background) {
            Write-AppLog '后台: 尝试更新驱动清单（8秒超时）...' -OnLog $OnLog
        } else {
            Write-AppLog '初始化: 正在同步驱动清单...' -OnLog $OnLog
        }
        try {
            $timeout = if ($Background) { 8 } else { 30 }
            $manifest = Sync-DriverManifest -OnLog $OnLog -TimeoutSec $timeout
            $online = $true
            Write-AppLog ("驱动清单 v{0} (在线)" -f $manifest.version) -OnLog $OnLog
        } catch {
            Write-AppLog ("在线更新跳过，使用内置清单 v{0}" -f $manifest.version) -OnLog $OnLog
        }
    } else {
        Write-AppLog ("使用缓存清单 v{0}" -f $manifest.version) -OnLog $OnLog
    }

    $driverDirs = @(Get-ChildItem (Join-Path (Get-AppRoot) 'Drivers') -Directory -EA SilentlyContinue)
    if ($driverDirs.Count -eq 0) {
        Write-AppLog '修复时将自动在线下载驱动包' -OnLog $OnLog
    } else {
        Write-AppLog ("本地驱动库 {0} 个包" -f $driverDirs.Count) -OnLog $OnLog
    }

    # Silently pre-install MSCatalogLTS in the background (no UI impact)
    try { Invoke-MSCatalogLTSPreinstall -OnLog $OnLog } catch {}

    Set-BootstrapState -ManifestVersion $manifest.version -OnlineSync $online
    return $manifest
}
