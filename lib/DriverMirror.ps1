# Remote driver mirror sync and package download

function Get-MirrorConfig {
    $root = Get-AppRoot
    $configPath = Join-Path $root 'driver_mirror.json'
    if (Test-Path $configPath) {
        return Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return [PSCustomObject]@{
        manifest_url = 'https://raw.githubusercontent.com/yanbai9188-oss/qudong/main/manifest.json'
    }
}

function Sync-DriverManifest {
    param(
        [scriptblock]$OnLog,
        [switch]$Force,
        [int]$TimeoutSec = 60
    )

    $config = Get-MirrorConfig
    $cacheDir = Join-Path (Get-AppDataRoot) 'Cache'
    $cachePath = Join-Path $cacheDir 'manifest.json'
    $localPath = Join-Path (Get-AppDataRoot) 'driver_packages.json'

    if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }

    $url = $config.manifest_url
    Write-AppLog "同步驱动清单: $url" -OnLog $OnLog

    try {
        try {
            Invoke-WebRequest -Uri $url -OutFile $cachePath -UseBasicParsing -TimeoutSec $TimeoutSec
        } catch {
            $fallbackUrl = $null
            if ($config.fallback_manifest_url) { $fallbackUrl = $config.fallback_manifest_url }
            if ($fallbackUrl) {
                Write-AppLog "主清单失败，尝试备用: $fallbackUrl" -OnLog $OnLog
                Invoke-WebRequest -Uri $fallbackUrl -OutFile $cachePath -UseBasicParsing -TimeoutSec $TimeoutSec
            } else {
                throw
            }
        }
        Copy-Item $cachePath $localPath -Force
        $manifest = Import-DriverManifest -Path $cachePath
        Write-AppLog "清单已更新: v$($manifest.version)" -OnLog $OnLog
        return $manifest
    } catch {
        Write-AppLog "远程同步失败: $($_.Exception.Message)" -OnLog $OnLog
        $fallback = Get-LocalManifestPath
        if ($fallback) {
            Write-AppLog "使用本地清单: $fallback" -OnLog $OnLog
            return Import-DriverManifest -Path $fallback
        }
        throw
    }
}

function Expand-DriverZip {
    param(
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$DestDir
    )
    if (Test-Path $DestDir) { Remove-Item $DestDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    Expand-Archive -Path $ZipPath -DestinationPath $DestDir -Force
}

function Download-DriverPackage {
    <#
    .SYNOPSIS
        Download a driver package using the multi-source engine.
        Delegates to Invoke-MultiSourceDriverDownload (DriverDownloader.ps1) which handles
        github / direct / catalog sources with automatic fallback.
    #>
    param(
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)][string]$PackageId,
        [scriptblock]$OnLog,
        [scriptblock]$OnProgress
    )

    # If the new multi-source engine is available, use it (preferred path)
    if (Get-Command Invoke-MultiSourceDriverDownload -ErrorAction SilentlyContinue) {
        Write-AppLog "下载驱动: $($Package.title) [$PackageId]" -OnLog $OnLog
        return Invoke-MultiSourceDriverDownload -Package $Package -PackageId $PackageId `
            -OnLog $OnLog -OnProgress $OnProgress
    }

    # ── Legacy path (no multi-source engine loaded) ───────────────────────────
    if (-not $Package.url) { throw "Package $PackageId has no download URL and multi-source engine not loaded" }

    $cacheDir    = Join-Path (Get-AppDataRoot) 'Cache'
    $driversRoot = Join-Path (Get-AppRoot) 'Drivers'
    $zipName     = [IO.Path]::GetFileName($Package.url)
    if (-not $zipName -or $zipName -notmatch '\.zip$') {
        $zipName = ($PackageId -replace '^Seed_', '').ToLower() + '.zip'
    }
    $zipPath  = Join-Path $cacheDir $zipName
    $destName = if ($Package.id) { [string]$Package.id } elseif ($Package.Id) { [string]$Package.Id } else { ($PackageId -replace '^Seed_', '').ToLower() }
    $destDir  = Join-Path $driversRoot $destName

    if ((Test-Path $destDir) -and @(Get-ChildItem $destDir -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue).Count -gt 0) {
        Write-AppLog "本地已有驱动包 (含 INF): $destName，跳过下载" -OnLog $OnLog
        return $destDir
    }

    Write-AppLog "下载: $($Package.title) ..." -OnLog $OnLog
    if ($OnProgress) { & $OnProgress 0 }

    $config = Get-MirrorConfig
    $urls   = @($Package.url)
    if ($config.fallback_release_base -and $Package.url -match 'yanbai9188-oss/qudong') {
        $fn = [IO.Path]::GetFileName($Package.url)
        if ($fn) { $urls += ($config.fallback_release_base.TrimEnd('/') + '/' + $fn) }
    }

    $downloaded = $false
    foreach ($tryUrl in $urls) {
        try {
            Write-AppLog "GET $tryUrl (8 线程)" -OnLog $OnLog
            Save-RemoteFile -Uri $tryUrl -Path $zipPath -TimeoutSec 7200 -Threads 8 -OnProgress {
                param($pct, $mb, $totalMb)
                if ($OnProgress) {
                    $label = if ($totalMb -gt 0) { "下载 ${mb}/${totalMb} MB" } else { "下载 ${mb} MB" }
                    & $OnProgress $pct $label
                }
            } -OnLog $OnLog
            $downloaded = $true
            break
        } catch {
            Write-AppLog "下载失败: $($_.Exception.Message)" -OnLog $OnLog
        }
    }
    if (-not $downloaded) { throw "所有下载地址均失败: $PackageId" }

    if ($Package.sha256) {
        $hash = Get-FileSha256 -Path $zipPath
        if ($hash -ne $Package.sha256.ToLower()) {
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            throw "SHA256 校验失败: $PackageId"
        }
        Write-AppLog 'SHA256 校验通过' -OnLog $OnLog
    }

    Expand-DriverZip -ZipPath $zipPath -DestDir $destDir
    if ($OnProgress) { & $OnProgress 100 '解压完成' }
    Write-AppLog "已解压到: $destDir" -OnLog $OnLog
    return $destDir
}
