# Cache Drivers\ INF hardware IDs for fast local matching

function Get-InfIndexPath {
    return Join-Path (Join-Path (Get-AppDataRoot) 'Cache') 'inf_index.json'
}

function Get-DriversIndexStamp {
    $root = Join-Path (Get-AppRoot) 'Drivers'
    if (-not (Test-Path $root)) { return 'empty' }

    $dirs = @(Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue)
    $latest = [datetime]::MinValue
    foreach ($dir in $dirs) {
        if ($dir.LastWriteTimeUtc -gt $latest) { $latest = $dir.LastWriteTimeUtc }
    }
    return ('{0}|{1:o}' -f $dirs.Count, $latest)
}

function Build-DriverInfIndex {
    param([scriptblock]$OnLog)

    $driversRoot = Join-Path (Get-AppRoot) 'Drivers'
    $entries = New-Object System.Collections.ArrayList
    $hwidMap = @{}

    if (-not (Test-Path $driversRoot)) {
        return [PSCustomObject]@{ version = 1; stamp = 'empty'; entries = @(); hwidMap = @{} }
    }

    Write-AppLog '正在构建驱动索引...' -OnLog $OnLog
    $idx = 0
    foreach ($dir in (Get-ChildItem -Path $driversRoot -Directory -ErrorAction SilentlyContinue)) {
        foreach ($inf in (Get-ChildItem -Path $dir.FullName -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue)) {
            $idx++
            if ($idx % 200 -eq 0) { Write-AppLog ("  索引进度: $idx ...") -OnLog $OnLog }
            $ids = @(Get-InfHardwareIds -InfPath $inf.FullName)
            if ($ids.Count -eq 0) { continue }
            [void]$entries.Add([PSCustomObject]@{
                folder = $dir.Name
                inf    = $inf.FullName.Substring($driversRoot.Length).TrimStart('\')
                hwids  = $ids
            })
            foreach ($id in $ids) {
                $key = (Normalize-HardwareId $id)
                if (-not $key) { continue }
                if (-not $hwidMap.ContainsKey($key)) { $hwidMap[$key] = @() }
                if ($hwidMap[$key] -notcontains $dir.Name) {
                    $hwidMap[$key] = @($hwidMap[$key]) + @($dir.Name)
                }
            }
        }
    }

    $index = [PSCustomObject]@{
        version  = 1
        built    = (Get-Date -Format 'o')
        stamp    = Get-DriversIndexStamp
        entries  = @($entries.ToArray())
        hwidMap  = $hwidMap
    }

    $path = Get-InfIndexPath
    ($index | ConvertTo-Json -Depth 8 -Compress) | Set-Content -Path $path -Encoding UTF8
    Write-AppLog ("驱动索引就绪: {0} 个 INF, {1} 个 HWID" -f $entries.Count, $hwidMap.Count) -OnLog $OnLog
    return $index
}

function Get-DriverInfIndex {
    param(
        [switch]$ForceRebuild,
        [scriptblock]$OnLog
    )

    $path = Get-InfIndexPath
    $stamp = Get-DriversIndexStamp

    if (-not $ForceRebuild -and (Test-Path $path)) {
        try {
            $cached = Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cached.stamp -eq $stamp) { return $cached }
        } catch { }
    }

    return Build-DriverInfIndex -OnLog $OnLog
}

function Test-LocalDriverLibraryReady {
    $root = Join-Path (Get-AppRoot) 'Drivers'
    if (-not (Test-Path $root)) { return $false }
    foreach ($dir in (Get-ChildItem $root -Directory -EA SilentlyContinue)) {
        $inf = Get-ChildItem $dir.FullName -Filter '*.inf' -Recurse -EA SilentlyContinue | Select-Object -First 1
        if ($inf) { return $true }
    }
    return $false
}

function Get-InfIndexHashtable {
    param($Index)
    if ($script:CachedInfIndexHashtable -and $script:CachedInfIndexStamp -eq $Index.stamp) {
        return $script:CachedInfIndexHashtable
    }
    $hash = @{}
    if ($Index.hwidMap) {
        foreach ($prop in $Index.hwidMap.PSObject.Properties) {
            $hash[$prop.Name] = @($prop.Value)
        }
    }
    $script:CachedInfIndexHashtable = $hash
    $script:CachedInfIndexStamp = $Index.stamp
    return $hash
}

function Find-LocalDriverFolderFast {
    param(
        [Parameter(Mandatory)][string[]]$DeviceIds,
        [hashtable]$HwidMap
    )
    foreach ($deviceId in $DeviceIds) {
        $d = Normalize-HardwareId $deviceId
        if (-not $d) { continue }
        if ($HwidMap.ContainsKey($d)) {
            $folders = @($HwidMap[$d])
            if ($folders.Count -gt 0) { return [string]$folders[0] }
        }
        $parts = $d -split '&'
        for ($i = $parts.Count; $i -ge 1; $i--) {
            $prefix = ($parts[0..($i - 1)] -join '&')
            foreach ($key in $HwidMap.Keys) {
                if ($key -eq $prefix -or $key.StartsWith($prefix)) {
                    $folders = @($HwidMap[$key])
                    if ($folders.Count -gt 0) { return [string]$folders[0] }
                }
            }
        }
    }
    return $null
}
function Find-LocalDriverByHardwareId {
    param(
        [Parameter(Mandatory)][string[]]$DeviceIds,
        [scriptblock]$OnLog
    )

    if (-not (Test-LocalDriverLibraryReady)) { return $null }

    $index = Get-DriverInfIndex -OnLog $OnLog
    if (-not $index -or -not $index.hwidMap) { return $null }

    $hwidMap = Get-InfIndexHashtable -Index $index
    $matchedFolder = Find-LocalDriverFolderFast -DeviceIds $DeviceIds -HwidMap $hwidMap

    if (-not $matchedFolder) { return $null }

    $driversRoot = Join-Path (Get-AppRoot) 'Drivers'
    $localPath = Join-Path $driversRoot $matchedFolder
    if (-not (Test-Path $localPath)) { return $null }

    $c = ConvertTo-PackageCandidate -PackageKey ('Local_' + $matchedFolder) -PackageRaw ([PSCustomObject]@{
        id           = $matchedFolder
        title        = $matchedFolder
        local_only   = $true
        whql         = $true
        signed       = $true
        confidence   = 'medium'
        success_rate = 0.9
    }) -Device $null
    $c | Add-Member -NotePropertyName _MatchHwids -NotePropertyValue @($DeviceIds) -Force
    $c.LocalPath = $localPath
    return $c
}
