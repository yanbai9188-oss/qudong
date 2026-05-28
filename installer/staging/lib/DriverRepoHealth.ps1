# Local driver repository health score (v1.6.5)

function Test-PackageLocalIntegrity {
    param(
        $PackageKey,
        $PackageRaw,
        [string]$DriversRoot
    )

    $id = if ($PackageRaw.id) { [string]$PackageRaw.id } else { ($PackageKey -replace '^Seed_', '') }
    $issues = New-Object System.Collections.ArrayList
    $level = 'pass'

    $folderCandidates = @(
        (Join-Path $DriversRoot $id)
        (Join-Path $DriversRoot ($PackageKey -replace '^Seed_', ''))
        (Join-Path $DriversRoot $PackageKey)
    )
    $folder = $folderCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    $zipName = if ($PackageRaw.url -match '/([^/]+\.zip)') { $matches[1] } else { "$id.zip" }
    $zipPath = Join-Path $DriversRoot $zipName
    $hasZip = Test-Path $zipPath
    $hasFolder = [bool]$folder

    if (-not $hasZip -and -not $hasFolder) {
        [void]$issues.Add('missing')
        return [PSCustomObject]@{ Id = $id; Level = 'fail'; Issues = @('missing'); HasInf = $false }
    }

    $infPath = $null
    if ($hasFolder) {
        $infPath = Get-ChildItem $folder -Filter '*.inf' -Recurse -EA SilentlyContinue | Select-Object -First 1
    }
    if (-not $infPath -and $hasZip) {
        $level = 'warn'
        [void]$issues.Add('zip_only')
    }
    elseif (-not $infPath) {
        [void]$issues.Add('no_inf')
        $level = 'fail'
    }

    if ($PackageRaw.sha256 -and $hasZip) {
        try {
            $hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -ne [string]$PackageRaw.sha256.ToLowerInvariant()) {
                [void]$issues.Add('sha_mismatch')
                if ($level -eq 'pass') { $level = 'warn' }
            }
        } catch {
            [void]$issues.Add('sha_error')
        }
    }
    elseif ($PackageRaw.sha256 -and -not $hasZip) {
        [void]$issues.Add('no_zip')
    }

    return [PSCustomObject]@{
        Id     = $id
        Level  = $level
        Issues = @($issues)
        HasInf = [bool]$infPath
    }
}

function Get-DriverRepositoryHealth {
    param(
        [string]$AppRoot = $null,
        [switch]$UpdateManifestSha
    )

    $root = if ($AppRoot) { $AppRoot } else { Get-AppRoot }
    $manifestPath = Join-Path $root 'driver_packages.json'
    if (-not (Test-Path $manifestPath)) {
        return [PSCustomObject]@{
            HealthPercent = 0
            TotalPackages = 0
            Valid = 0
            Warning = 0
            Failed = 0
            SummaryLine = '驱动库：未找到 manifest'
            Details = @()
        }
    }

    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $driversRoot = Join-Path $root 'Drivers'
    $pass = 0
    $warn = 0
    $fail = 0
    $details = New-Object System.Collections.ArrayList
    $manifestDirty = $false

    foreach ($prop in $manifest.packages.PSObject.Properties) {
        $check = Test-PackageLocalIntegrity -PackageKey $prop.Name -PackageRaw $prop.Value -DriversRoot $driversRoot
        [void]$details.Add($check)
        switch ($check.Level) {
            'pass' { $pass++ }
            'warn' { $warn++ }
            default { $fail++ }
        }

        if ($UpdateManifestSha -and ($check.Issues -contains 'sha_mismatch')) {
            $id = if ($prop.Value.id) { [string]$prop.Value.id } else { ($prop.Name -replace '^Seed_', '') }
            $zipName = if ($prop.Value.url -match '/([^/]+\.zip)') { $matches[1] } else { "$id.zip" }
            $zipPath = Join-Path $driversRoot $zipName
            if (Test-Path $zipPath) {
                $newHash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
                $prop.Value.sha256 = $newHash
                $manifestDirty = $true
            }
        }
    }

    if ($manifestDirty) {
        ($manifest | ConvertTo-Json -Depth 20) | Set-Content $manifestPath -Encoding UTF8
    }

    $total = @($manifest.packages.PSObject.Properties).Count

    # Distinguish "all missing" (drivers not yet downloaded - normal first run)
    # from real corruption (sha_mismatch / no_inf). The former is the expected
    # state for the lean online installer and must not look like a 0% failure.
    $allMissing = $false
    if ($total -gt 0 -and $fail -eq $total -and $pass -eq 0 -and $warn -eq 0) {
        $allMissing = $true
        foreach ($d in $details) {
            if ($d.Issues -and ($d.Issues -notcontains 'missing')) {
                $allMissing = $false
                break
            }
        }
    }

    if ($allMissing) {
        return [PSCustomObject]@{
            HealthPercent = 100
            TotalPackages = $total
            Valid         = $total
            Warning       = 0
            Failed        = 0
            CachedCount   = 0
            IsLazyCache   = $true
            SummaryLine   = ('在线模式：{0} 个驱动包已注册，将在修复时按需下载' -f $total)
            ShortLine     = ('在线模式 · {0} 个驱动包' -f $total)
            Details       = @($details.ToArray())
            ManifestUpdated = $manifestDirty
        }
    }

    $score = if ($total -gt 0) {
        [int][Math]::Round((($pass + $warn * 0.5) / $total) * 100)
    } else { 0 }

    return [PSCustomObject]@{
        HealthPercent = $score
        TotalPackages = $total
        Valid         = $pass
        Warning       = $warn
        Failed        = $fail
        CachedCount   = $pass + $warn
        IsLazyCache   = $false
        SummaryLine   = ('驱动库健康：{0}%（已缓存 {1} / 警告 {2} / 失败 {3}）' -f $score, $pass, $warn, $fail)
        ShortLine     = ('驱动库健康 {0}%' -f $score)
        Details       = @($details.ToArray())
        ManifestUpdated = $manifestDirty
    }
}

function Repair-DriverRepository {
    param(
        [string]$AppRoot = $null,
        [switch]$UpdateManifestSha,
        [switch]$DownloadMissing,
        [scriptblock]$OnLog
    )

    $root = if ($AppRoot) { $AppRoot } else { Get-AppRoot }
    $manifestPath = Join-Path $root 'driver_packages.json'
    if (-not (Test-Path $manifestPath)) {
        throw '未找到 driver_packages.json'
    }

    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $health = Get-DriverRepositoryHealth -AppRoot $root -UpdateManifestSha:$UpdateManifestSha

    if ($DownloadMissing) {
        foreach ($check in @($health.Details | Where-Object { $_.Issues -contains 'missing' })) {
            $pkgRaw = $null
            $pkgKey = $null
            foreach ($prop in $manifest.packages.PSObject.Properties) {
                $id = if ($prop.Value.id) { [string]$prop.Value.id } else { ($prop.Name -replace '^Seed_', '') }
                if ($id -eq $check.Id) {
                    $pkgRaw = $prop.Value
                    $pkgKey = $prop.Name
                    break
                }
            }
            if (-not $pkgRaw -or -not $pkgRaw.url) {
                Write-AppLog ("跳过缺失包（无下载地址）: {0}" -f $check.Id) -OnLog $OnLog
                continue
            }
            try {
                $candidate = ConvertTo-PackageCandidate -PackageKey $pkgKey -PackageRaw $pkgRaw -Device $null
                Write-AppLog ("补下载: {0}" -f $check.Id) -OnLog $OnLog
                Download-DriverPackage -Package $candidate -PackageId $check.Id -OnLog $OnLog | Out-Null
            } catch {
                Write-AppLog ("补下载失败 {0}: {1}" -f $check.Id, $_.Exception.Message) -OnLog $OnLog
            }
        }
    }

    return (Get-DriverRepositoryHealth -AppRoot $root -UpdateManifestSha:$UpdateManifestSha)
}
