# DriverDownloader.ps1 — Multi-source driver download engine
#
# Manifest 'sources' array schema (ordered, first-success-wins):
#
#   { "type": "github",  "url": "https://github.com/.../releases/download/.../pkg.zip",
#                        "sha256": "<hex>" }
#
#   { "type": "direct",  "url": "https://vendor-cdn.example.com/driver.zip",
#                        "sha256": "<hex>",          # optional
#                        "extract": "zip|exe|cab|none" }
#
#   { "type": "catalog", "hwids":    ["PCI\\VEN_...", ...],   # searched in order
#                        "keywords": ["Intel WiFi Win10 64-bit", ...] }  # keyword fallback
#
# Packages without a 'sources' field use the legacy 'url' field (backward compat).

function Invoke-MultiSourceDriverDownload {
    <#
    .SYNOPSIS
        Download a driver package trying each source in priority order.
    .OUTPUTS
        Path to the extracted driver folder on success; throws on total failure.
    #>
    param(
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)][string]$PackageId,
        [string]$DestDir = '',
        [scriptblock]$OnLog,
        [scriptblock]$OnProgress
    )

    $pkgId  = if ($Package.id) { [string]$Package.id } else { ($PackageId -replace '^Seed_', '').ToLower() }
    $root   = Get-AppRoot
    if (-not $DestDir) {
        $DestDir = Join-Path (Join-Path $root 'Drivers') $pkgId
    }

    # ── Check local cache first ───────────────────────────────────────────────
    if ((Test-Path $DestDir) -and (@(Get-ChildItem $DestDir -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue).Count -gt 0)) {
        Write-AppLog "本地已有驱动包 (含 INF): $pkgId，跳过下载" -OnLog $OnLog
        return $DestDir
    }

    # ── Build source list ─────────────────────────────────────────────────────
    $sources = @()

    if ($Package.sources) {
        $sources += @($Package.sources)
    }

    # Backward-compat: legacy 'url' field becomes a github/direct source
    if ($Package.url -and -not ($sources | Where-Object { $_.url -eq $Package.url })) {
        $legacySrc = @{ type = 'github'; url = [string]$Package.url }
        if ($Package.sha256) { $legacySrc.sha256 = [string]$Package.sha256 }
        $sources += $legacySrc
    }

    # Auto-generate catalog source from package hwids if no other catalog source given
    if ($Package.hwids -and -not ($sources | Where-Object { $_.type -eq 'catalog' })) {
        $sources += @(@{ type = 'catalog'; hwids = @($Package.hwids) })
    }

    if ($sources.Count -eq 0) {
        throw "Package $PackageId has no download sources defined"
    }

    # ── Try each source in order ──────────────────────────────────────────────
    $lastErr = ''
    foreach ($src in $sources) {
        $srcType = [string]$src.type
        Write-AppLog "尝试下载源: [$srcType] $pkgId" -OnLog $OnLog
        try {
            $result = switch ($srcType) {
                'github'  { Invoke-GithubSourceDownload  -Source $src -Package $Package -PackageId $PackageId -DestDir $DestDir -OnLog $OnLog -OnProgress $OnProgress }
                'direct'  { Invoke-DirectSourceDownload  -Source $src -Package $Package -PackageId $PackageId -DestDir $DestDir -OnLog $OnLog -OnProgress $OnProgress }
                'catalog' { Invoke-CatalogSourceDownload -Source $src -Package $Package -PackageId $PackageId -DestDir $DestDir -OnLog $OnLog -OnProgress $OnProgress }
                default   { Write-AppLog "未知下载源类型: $srcType" -OnLog $OnLog; $null }
            }
            if ($result) {
                Write-AppLog "下载成功 [$srcType]: $result" -OnLog $OnLog
                return $result
            }
        } catch {
            $lastErr = $_.Exception.Message
            Write-AppLog "下载源 [$srcType] 失败: $lastErr" -OnLog $OnLog
        }
    }

    throw "所有下载源均失败 (${pkgId}): $lastErr"
}

# ─────────────────────────────────────────────────────────────────────────────
# GitHub source (zip download + sha256 verify + extract)
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-GithubSourceDownload {
    param($Source, $Package, [string]$PackageId, [string]$DestDir, [scriptblock]$OnLog, [scriptblock]$OnProgress)

    $url = [string]$Source.url
    if (-not $url) { throw 'github source: no url' }

    $sha256   = if ($Source.sha256) { [string]$Source.sha256 } elseif ($Package.sha256) { [string]$Package.sha256 } else { $null }
    $cacheDir = Join-Path (Get-AppDataRoot) 'Cache'
    if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }

    $zipName  = [IO.Path]::GetFileName($url)
    if (-not $zipName -or $zipName -notmatch '\.(zip|cab|7z)$') { $zipName = $PackageId + '.zip' }
    $zipPath  = Join-Path $cacheDir $zipName

    # Use mirror fallback if configured
    $config = if (Get-Command Get-MirrorConfig -ErrorAction SilentlyContinue) { Get-MirrorConfig } else { @{} }
    $urls   = @($url)
    if ($config.fallback_release_base -and $url -match 'github\.com') {
        $fn = [IO.Path]::GetFileName($url)
        if ($fn) { $urls += ($config.fallback_release_base.TrimEnd('/') + '/' + $fn) }
    }

    $downloaded = $false
    foreach ($tryUrl in $urls) {
        try {
            Write-AppLog "GET $tryUrl" -OnLog $OnLog
            Save-RemoteFile -Uri $tryUrl -Path $zipPath -TimeoutSec 7200 -Threads 8 -OnProgress {
                param($pct, $mb, $totalMb)
                if ($OnProgress) {
                    $lbl = if ($totalMb -gt 0) { "下载 ${mb}/${totalMb} MB" } else { "下载 ${mb} MB" }
                    & $OnProgress $pct $lbl
                }
            } -OnLog $OnLog
            $downloaded = $true
            break
        } catch {
            Write-AppLog "GET $tryUrl 失败: $($_.Exception.Message)" -OnLog $OnLog
        }
    }
    if (-not $downloaded) { throw "GitHub download failed for all URLs" }

    # SHA256 verify
    if ($sha256) {
        Write-AppLog 'SHA256 校验...' -OnLog $OnLog
        $actual = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
        if ($actual -ne $sha256.ToUpper()) {
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            throw "SHA256 mismatch: expected $sha256 got $actual"
        }
        Write-AppLog 'SHA256 校验通过' -OnLog $OnLog
    }

    Expand-DriverZip -ZipPath $zipPath -DestDir $DestDir
    return $DestDir
}

# ─────────────────────────────────────────────────────────────────────────────
# Direct URL source (vendor CDN: Intel CDN, OEM mirrors, etc.)
# Supports .zip, .cab, .exe (silent-install EXE extracts INF to DestDir)
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-DirectSourceDownload {
    param($Source, $Package, [string]$PackageId, [string]$DestDir, [scriptblock]$OnLog, [scriptblock]$OnProgress)

    $url = [string]$Source.url
    if (-not $url) { throw 'direct source: no url' }

    $sha256   = if ($Source.sha256) { [string]$Source.sha256 } else { $null }
    $extract  = if ($Source.extract) { [string]$Source.extract } else { 'auto' }
    $cacheDir = Join-Path (Get-AppDataRoot) 'Cache'
    if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }

    $ext      = [IO.Path]::GetExtension($url).ToLower().TrimStart('.')
    $fileName = [IO.Path]::GetFileName(($url -split '\?' | Select-Object -First 1))
    if (-not $fileName) { $fileName = $PackageId + '.bin' }
    $dlPath   = Join-Path $cacheDir $fileName

    Write-AppLog "直链下载: $url" -OnLog $OnLog
    Save-RemoteFile -Uri $url -Path $dlPath -TimeoutSec 7200 -Threads 4 -OnProgress {
        param($pct, $mb, $totalMb)
        if ($OnProgress) {
            $lbl = if ($totalMb -gt 0) { "下载 ${mb}/${totalMb} MB" } else { "下载 ${mb} MB" }
            & $OnProgress $pct $lbl
        }
    } -OnLog $OnLog

    if ($sha256) {
        Write-AppLog 'SHA256 校验...' -OnLog $OnLog
        $actual = (Get-FileHash -Path $dlPath -Algorithm SHA256).Hash
        if ($actual -ne $sha256.ToUpper()) {
            Remove-Item $dlPath -Force -ErrorAction SilentlyContinue
            throw "SHA256 mismatch"
        }
        Write-AppLog 'SHA256 校验通过' -OnLog $OnLog
    }

    if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Force -Path $DestDir | Out-Null }

    # Determine extraction method
    $method = $extract
    if ($method -eq 'auto') {
        $method = switch ($ext) { 'zip' { 'zip' } 'cab' { 'cab' } 'exe' { 'exe_extract' } '7z' { '7z' } default { 'zip' } }
    }

    switch ($method) {
        'zip' {
            Expand-Archive -Path $dlPath -DestinationPath $DestDir -Force
        }
        'cab' {
            $proc = Start-Process expand.exe -ArgumentList @($dlPath, '-F:*', $DestDir) -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -ne 0) { throw "expand.exe failed ($($proc.ExitCode))" }
        }
        'exe_extract' {
            # Try common silent-extract flags used by Intel/NVIDIA/AMD setup EXEs
            # NOTE: DO NOT use $args — it is a PS automatic variable (function's unbound params).
            $extracted = $false
            foreach ($exeArgs in @(
                @('/s', '/e', "/f:`"$DestDir`""),
                @('-s', '-extract', $DestDir),
                @('/exenoui', '/qn', "/extractpath:`"$DestDir`"")
            )) {
                try {
                    $p = Start-Process $dlPath -ArgumentList $exeArgs -Wait -PassThru -NoNewWindow
                    $infs = @(Get-ChildItem $DestDir -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue)
                    if ($infs.Count -gt 0) { $extracted = $true; break }
                } catch { continue }
            }
            if (-not $extracted) {
                # Fallback: use 7-Zip if available
                $7z = @('C:\Program Files\7-Zip\7z.exe', 'C:\Program Files (x86)\7-Zip\7z.exe') |
                    Where-Object { Test-Path $_ } | Select-Object -First 1
                if ($7z) {
                    $p = Start-Process $7z -ArgumentList @('x', "-o`"$DestDir`"", '-y', "`"$dlPath`"") -Wait -PassThru -NoNewWindow
                    $extracted = $p.ExitCode -eq 0
                }
                if (-not $extracted) { throw "EXE extraction failed — no INF found in $DestDir" }
            }
        }
        'none' {
            # File is already in usable form (e.g. a direct .inf, though unusual)
            Copy-Item $dlPath $DestDir -Force
        }
    }

    $infCount = @(Get-ChildItem $DestDir -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue).Count
    if ($infCount -eq 0) { throw "Direct download extracted but no INF files found in $DestDir" }

    Write-AppLog "直链下载完成，找到 $infCount 个 INF: $DestDir" -OnLog $OnLog
    return $DestDir
}

# ─────────────────────────────────────────────────────────────────────────────
# Windows Update Catalog source
# Searches by HWID first, then by keyword fallbacks
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-CatalogSourceDownload {
    param($Source, $Package, [string]$PackageId, [string]$DestDir, [scriptblock]$OnLog, [scriptblock]$OnProgress)

    if (-not (Get-Command Download-CatalogDriver -ErrorAction SilentlyContinue)) {
        throw 'CatalogDownloader not loaded'
    }

    # Build HWID list from source definition or package hwids
    $hwids = @()
    if ($Source.hwids) { $hwids += @($Source.hwids) }
    if ($Package.hwids -and $hwids.Count -eq 0) { $hwids += @($Package.hwids) }

    # Build keyword fallback list
    $keywords = @()
    if ($Source.keywords) { $keywords += @($Source.keywords) }

    # Derive keywords from package title if none provided
    if ($keywords.Count -eq 0 -and $Package.title) {
        $keywords += [string]$Package.title
    }

    if ($hwids.Count -eq 0 -and $keywords.Count -eq 0) {
        throw 'catalog source: no hwids or keywords to search'
    }

    if ($OnProgress) { & $OnProgress 5 '正在搜索驱动目录...' }

    # Try each HWID
    foreach ($hwid in $hwids) {
        Write-AppLog "Catalog HWID 搜索: $hwid" -OnLog $OnLog
        try {
            $result = Download-CatalogDriver -HardwareId $hwid -DestDir $DestDir `
                -OsFilter @('Windows 10', 'Windows 11') `
                -KeywordFallback $keywords -OnLog $OnLog
            if ($result) { return $result }
        } catch {
            Write-AppLog "Catalog HWID [$hwid] 失败: $($_.Exception.Message)" -OnLog $OnLog
        }
    }

    # Try keyword-only search
    if ($keywords.Count -gt 0) {
        Write-AppLog "Catalog 关键词搜索: $($keywords[0])" -OnLog $OnLog
        try {
            $result = Download-CatalogDriver -HardwareId $keywords[0] -DestDir $DestDir `
                -OsFilter @('Windows 10', 'Windows 11') -OnLog $OnLog
            if ($result) { return $result }
        } catch {
            Write-AppLog "Catalog 关键词失败: $($_.Exception.Message)" -OnLog $OnLog
        }
    }

    return $null
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
function Get-DriverCacheDir {
    $dir = Join-Path (Get-AppDataRoot) 'Cache'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    return $dir
}

function Get-DriverExtractDir {
    param([string]$PackageId)
    $pkgId = ($PackageId -replace '^Seed_', '').ToLower()
    return Join-Path (Join-Path (Get-AppRoot) 'Drivers') $pkgId
}
