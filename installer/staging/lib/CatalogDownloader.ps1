# CatalogDownloader.ps1 — Windows Update Catalog driver downloader
#
# Strategy (in order):
#   1. MSCatalogLTS module (PowerShell Gallery, maintained)  → most reliable
#   2. Hand-rolled HTTP scraper                              → fallback if module unavailable
#
# MSCatalogLTS: https://github.com/Marco-online/MSCatalogLTS
# Auto-installs on first use; result cached to avoid repeated PSGallery hits.

# ─────────────────────────────────────────────────────────────────────────────
# MSCatalogLTS module bootstrap
# ─────────────────────────────────────────────────────────────────────────────

$script:_mscatalog_checked = $false
$script:_mscatalog_ready   = $false

function Get-MSCatalogStatusPath {
    return Join-Path (Join-Path (Get-AppDataRoot) 'Cache') 'mscataloglts_status.json'
}

function Initialize-MSCatalogLTS {
    <#
    .SYNOPSIS
        Ensure MSCatalogLTS is available. Tries PSGallery install once per session.
        Returns $true if module is usable.
    #>
    param([scriptblock]$OnLog)

    if ($script:_mscatalog_checked) { return $script:_mscatalog_ready }
    $script:_mscatalog_checked = $true

    # Already loaded in this session?
    if (Get-Command Get-MSCatalogUpdate -ErrorAction SilentlyContinue) {
        $script:_mscatalog_ready = $true
        return $true
    }

    # Already installed (but not imported)?
    if (Get-Module -ListAvailable -Name MSCatalogLTS -ErrorAction SilentlyContinue) {
        try {
            Import-Module MSCatalogLTS -Force -ErrorAction Stop
            Write-AppLog 'MSCatalogLTS 模块已加载' -OnLog $OnLog
            $script:_mscatalog_ready = $true
            return $true
        } catch {
            Write-AppLog "MSCatalogLTS 导入失败: $($_.Exception.Message)" -OnLog $OnLog
        }
    }

    # Check cached status — avoid hammering PSGallery on every run
    $statusPath = Get-MSCatalogStatusPath
    if (Test-Path $statusPath) {
        try {
            $st = Get-Content $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
            # If install failed recently, don't retry for 24h
            if ($st.status -eq 'failed' -and $st.timestamp) {
                $age = (Get-Date) - [DateTime]::Parse($st.timestamp)
                if ($age.TotalHours -lt 24) {
                    Write-AppLog 'MSCatalogLTS: 上次安装失败，跳过重试 (24h 冷却)' -OnLog $OnLog
                    return $false
                }
            }
        } catch {}
    }

    # Try to install from PSGallery
    Write-AppLog 'MSCatalogLTS: 首次使用，正在从 PSGallery 安装...' -OnLog $OnLog
    $cacheDir = Split-Path $statusPath -Parent
    if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }

    $installed = $false
    try {
        # Ensure NuGet provider without interactive prompt
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue | Where-Object Version -ge '2.8.5.201')) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
        }

        # Install module to CurrentUser scope (no admin required)
        Install-Module -Name MSCatalogLTS -Scope CurrentUser -Force -AllowClobber `
            -Repository PSGallery -ErrorAction Stop

        Import-Module MSCatalogLTS -Force -ErrorAction Stop
        Write-AppLog 'MSCatalogLTS 安装成功' -OnLog $OnLog
        $installed = $true
        $script:_mscatalog_ready = $true

        [PSCustomObject]@{ status = 'ok'; timestamp = (Get-Date -Format 'o') } |
            ConvertTo-Json | Set-Content $statusPath -Encoding UTF8
    } catch {
        Write-AppLog "MSCatalogLTS 安装失败: $($_.Exception.Message)" -OnLog $OnLog
        [PSCustomObject]@{ status = 'failed'; timestamp = (Get-Date -Format 'o'); error = $_.Exception.Message } |
            ConvertTo-Json | Set-Content $statusPath -Encoding UTF8
    }

    return $installed
}

# ─────────────────────────────────────────────────────────────────────────────
# Primary: MSCatalogLTS-based download
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-MSCatalogDownload {
    <#
    .SYNOPSIS
        Search Windows Update Catalog via MSCatalogLTS and download the best match.
    .OUTPUTS
        Path to extracted driver folder, or $null on failure.
    #>
    param(
        [Parameter(Mandatory)][string]$SearchQuery,
        [Parameter(Mandatory)][string]$DestDir,
        [string[]]$OsFilter    = @('Windows 10', 'Windows 11'),
        [string]$Architecture  = 'x64',
        [string[]]$Keywords    = @(),     # extra search terms tried as fallback
        [scriptblock]$OnLog
    )

    if (-not (Initialize-MSCatalogLTS -OnLog $OnLog)) { return $null }

    Write-AppLog "MSCatalogLTS 搜索: $SearchQuery" -OnLog $OnLog

    $found = $null
    $queries = @($SearchQuery) + $Keywords
    foreach ($q in $queries) {
        try {
            $results = @(Get-MSCatalogUpdate -Search $q -Architecture $Architecture -ErrorAction Stop)
            if ($results.Count -eq 0) { continue }

            # Rank: prefer Win10/Win11, prefer Drivers classification, prefer newest
            $ranked = $results | ForEach-Object {
                $score = 0
                $prod  = [string]$_.Products
                $title = [string]$_.Title
                foreach ($os in $OsFilter) {
                    if ($prod -match [regex]::Escape($os)) { $score += 20 }
                }
                if ($title -match 'DCH')                         { $score += 5  }
                if ($prod  -match 'Drivers')                     { $score += 10 }
                if ($title -notmatch 'arm|ARM|Preview|beta|Beta') { $score += 3  }
                [PSCustomObject]@{ Update = $_; Score = $score }
            } | Sort-Object Score -Descending

            $found = $ranked[0].Update
            Write-AppLog "MSCatalogLTS 找到: $($found.Title) ($($found.Size))" -OnLog $OnLog
            break
        } catch {
            Write-AppLog "MSCatalogLTS 搜索 [$q] 失败: $($_.Exception.Message)" -OnLog $OnLog
        }
    }

    if (-not $found) { return $null }

    # Download to a temp subdirectory, then expand CAB
    $tmpDown = Join-Path (Get-AppDataRoot) 'Cache\_mscatalog_dl'
    if (Test-Path $tmpDown) { Remove-Item $tmpDown -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $tmpDown | Out-Null

    try {
        Write-AppLog "MSCatalogLTS 下载中..." -OnLog $OnLog
        Save-MSCatalogUpdate -Update $found -Destination $tmpDown -ErrorAction Stop

        # Find the downloaded file (.cab or .msu)
        $dl = Get-ChildItem $tmpDown -File -Recurse | Select-Object -First 1
        if (-not $dl) { throw 'Save-MSCatalogUpdate 没有下载到文件' }

        Write-AppLog "下载完成: $($dl.Name) ($([Math]::Round($dl.Length/1MB,1)) MB)" -OnLog $OnLog

        # Extract to DestDir
        if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Force -Path $DestDir | Out-Null }

        switch ($dl.Extension.ToLower()) {
            '.cab' {
                $proc = Start-Process expand.exe -ArgumentList @("`"$($dl.FullName)`"", '-F:*', "`"$DestDir`"") `
                    -Wait -PassThru -NoNewWindow
                if ($proc.ExitCode -ne 0) { throw "expand.exe exit $($proc.ExitCode)" }
            }
            '.msu' {
                # Extract the inner CAB from the MSU, then expand the CAB into DestDir
                $innerCabDir = Join-Path $tmpDown 'msu_inner'
                New-Item -ItemType Directory -Force -Path $innerCabDir | Out-Null
                $proc = Start-Process expand.exe -ArgumentList @("`"$($dl.FullName)`"", '-F:*', "`"$innerCabDir`"") `
                    -Wait -PassThru -NoNewWindow
                if ($proc.ExitCode -ne 0) { throw "expand.exe (MSU stage 1) exit $($proc.ExitCode)" }
                $innerCab = Get-ChildItem $innerCabDir -Filter '*.cab' | Select-Object -First 1
                if ($innerCab) {
                    $proc2 = Start-Process expand.exe -ArgumentList @("`"$($innerCab.FullName)`"", '-F:*', "`"$DestDir`"") `
                        -Wait -PassThru -NoNewWindow
                    if ($proc2.ExitCode -ne 0) { throw "expand.exe (MSU stage 2 CAB) exit $($proc2.ExitCode)" }
                } else {
                    throw 'MSU 解压后未找到内层 .cab 文件'
                }
            }
            default {
                Copy-Item $dl.FullName $DestDir -Force
            }
        }

        # Write provenance file
        Set-Content -Path (Join-Path $DestDir 'source.txt') -Value @(
            "Source: MSCatalogLTS / Microsoft Update Catalog",
            "Title: $($found.Title)",
            "Size: $($found.Size)",
            "UpdateId: $(if ($found.Guid) { $found.Guid } elseif ($found.UpdateId) { $found.UpdateId } else { '' })",
            "Downloaded: $(Get-Date -Format 'o')"
        ) -Encoding UTF8

        $infCount = @(Get-ChildItem $DestDir -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue).Count
        if ($infCount -gt 0) {
            Write-AppLog "Catalog 驱动解压完成，$infCount 个 INF: $DestDir" -OnLog $OnLog
            return $DestDir
        } else {
            Write-AppLog "Catalog 解压后未找到 INF (可能是固件或补丁包): $DestDir" -OnLog $OnLog
            # Still return — caller can try pnputil on the folder
            return $DestDir
        }
    } catch {
        Write-AppLog "MSCatalogLTS 下载/解压失败: $($_.Exception.Message)" -OnLog $OnLog
        return $null
    } finally {
        Remove-Item $tmpDown -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Fallback: hand-rolled HTTP scraper (no external dependencies)
# ─────────────────────────────────────────────────────────────────────────────

function Get-CatalogCabUrl {
    param([Parameter(Mandatory)][string]$UpdateId)

    $base    = 'https://www.catalog.update.microsoft.com/'
    $ua      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

    foreach ($path in @('Home.aspx', "Search.aspx?q=$UpdateId", "ScopedViewInline.aspx?updateid=$UpdateId")) {
        try { Invoke-WebRequest -Uri ($base + $path) -WebSession $session -Headers @{ 'User-Agent' = $ua } `
            -UseBasicParsing -TimeoutSec 30 | Out-Null } catch {}
    }

    $payload = ConvertTo-Json -Compress -InputObject @(@{ size = 0; updateID = $UpdateId; uidInfo = $UpdateId })
    $body    = ('updateIDs=' + [uri]::EscapeDataString($payload) + '&updateIDsBlocked=')
    $resp    = Invoke-WebRequest -Uri ($base + 'DownloadDialog.aspx') -Method POST -Body $body `
        -ContentType 'application/x-www-form-urlencoded' -WebSession $session `
        -Headers @{ 'User-Agent' = $ua; 'Referer' = ($base + 'Search.aspx') } -UseBasicParsing -TimeoutSec 60

    $m = [regex]::Match($resp.Content, "downloadInformation\[0\]\.files\[0\]\.url\s*=\s*'([^']+)'")
    if ($m.Success) { return $m.Groups[1].Value }

    $m2 = [regex]::Match($resp.Content, 'https://catalog\.s\.download\.windowsupdate\.com[^''"\s>]+')
    if ($m2.Success) { return $m2.Value }

    return $null
}

function Search-CatalogUpdateId {
    param([Parameter(Mandatory)][string]$HardwareId, [scriptblock]$OnLog)
    return Search-CatalogUpdateIdByQuery -Query $HardwareId -OnLog $OnLog
}

function Search-CatalogUpdateIdByQuery {
    param(
        [Parameter(Mandatory)][string]$Query,
        [string[]]$OsFilter    = @(),
        [string]$Architecture  = 'x64',
        [scriptblock]$OnLog
    )

    $encoded = [uri]::EscapeDataString($Query)
    $url     = "https://www.catalog.update.microsoft.com/Search.aspx?q=$encoded"
    Write-AppLog "Catalog HTTP 搜索: $Query" -OnLog $OnLog

    try {
        $resp     = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 45 -Headers @{
            'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }
        $allMatch = [regex]::Matches($resp.Content, 'goToDetails\("([0-9a-f-]{36})"\)')
        if ($allMatch.Count -eq 0) { return $null }

        if ($OsFilter.Count -eq 0 -and -not $Architecture) { return $allMatch[0].Groups[1].Value }

        $scored = $allMatch | ForEach-Object {
            $id    = $_.Groups[1].Value
            $pre   = $resp.Content.Substring([Math]::Max(0, $_.Index - 400), [Math]::Min(400, $_.Index))
            $score = 0
            foreach ($os in $OsFilter) { if ($pre -match [regex]::Escape($os)) { $score += 10 } }
            if ($Architecture -and $pre -match [regex]::Escape($Architecture)) { $score += 5 }
            [PSCustomObject]@{ Id = $id; Score = $score }
        } | Sort-Object Score -Descending

        return $scored[0].Id
    } catch {
        Write-AppLog "Catalog HTTP 搜索失败: $($_.Exception.Message)" -OnLog $OnLog
        return $null
    }
}

function Download-CatalogUpdate {
    param(
        [Parameter(Mandatory)][string]$UpdateId,
        [Parameter(Mandatory)][string]$DestDir,
        [string]$Label = '',
        [scriptblock]$OnLog
    )

    $cabUrl = Get-CatalogCabUrl -UpdateId $UpdateId
    if (-not $cabUrl) { Write-AppLog "Catalog: CAB URL 未找到 ($UpdateId)" -OnLog $OnLog; return $null }

    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    $cabPath = Join-Path $DestDir 'catalog_driver.cab'
    Write-AppLog "下载 Catalog CAB..." -OnLog $OnLog
    Invoke-WebRequest -Uri $cabUrl -OutFile $cabPath -UseBasicParsing -TimeoutSec 7200

    $proc = Start-Process expand.exe -ArgumentList @("`"$cabPath`"", '-F:*', "`"$DestDir`"") -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) { throw "expand.exe exit $($proc.ExitCode)" }

    Set-Content -Path (Join-Path $DestDir 'source.txt') -Value @(
        'Source: Microsoft Update Catalog (HTTP)',
        "UpdateId: $UpdateId",
        "Label: $Label",
        $cabUrl
    ) -Encoding UTF8

    return $DestDir
}

# ─────────────────────────────────────────────────────────────────────────────
# Public entry point (used by DriverDownloader.ps1 → Invoke-CatalogSourceDownload)
# ─────────────────────────────────────────────────────────────────────────────

function Download-CatalogDriver {
    <#
    .SYNOPSIS
        Download a driver from Windows Update Catalog.
        Tries MSCatalogLTS first, falls back to HTTP scraper.
    #>
    param(
        [Parameter(Mandatory)][string]$HardwareId,
        [Parameter(Mandatory)][string]$DestDir,
        [string[]]$KeywordFallback = @(),
        [string[]]$OsFilter        = @('Windows 10', 'Windows 11'),
        [string]$Architecture      = 'x64',
        [scriptblock]$OnLog
    )

    # ── Path 1: MSCatalogLTS ──────────────────────────────────────────────────
    $result = Invoke-MSCatalogDownload -SearchQuery $HardwareId -DestDir $DestDir `
        -OsFilter $OsFilter -Architecture $Architecture -Keywords $KeywordFallback -OnLog $OnLog
    if ($result) { return $result }

    Write-AppLog 'MSCatalogLTS 未找到结果，切换到 HTTP 刮屏...' -OnLog $OnLog

    # ── Path 2: HTTP scraper ──────────────────────────────────────────────────
    $updateId = Search-CatalogUpdateId -HardwareId $HardwareId -OnLog $OnLog

    if (-not $updateId -and $KeywordFallback.Count -gt 0) {
        foreach ($kw in $KeywordFallback) {
            $updateId = Search-CatalogUpdateIdByQuery -Query $kw -OsFilter $OsFilter -Architecture $Architecture -OnLog $OnLog
            if ($updateId) { break }
        }
    }

    # Last resort: search the VEN_xxxx&DEV_xxxx portion only
    if (-not $updateId) {
        $shortId = ($HardwareId -split '\\' | Select-Object -Last 1) -replace '&.*', ''
        if ($shortId -and $shortId.Length -gt 4) {
            $updateId = Search-CatalogUpdateIdByQuery -Query $shortId -OsFilter $OsFilter `
                -Architecture $Architecture -OnLog $OnLog
        }
    }

    if (-not $updateId) {
        Write-AppLog "Catalog: 全部搜索策略均未找到驱动 [$HardwareId]" -OnLog $OnLog
        return $null
    }

    return Download-CatalogUpdate -UpdateId $updateId -DestDir $DestDir -Label $HardwareId -OnLog $OnLog
}

function Get-CatalogSearchUrl {
    param([string]$HardwareId)
    return "https://www.catalog.update.microsoft.com/Search.aspx?q=$([uri]::EscapeDataString($HardwareId))"
}
