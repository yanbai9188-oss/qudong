# Driver source / network status for UI

function Test-NetworkAvailable {
    param([int]$TimeoutSec = 3)
    try {
        $r = Invoke-WebRequest -Uri 'https://github.com' -UseBasicParsing -TimeoutSec $TimeoutSec -Method Head
        return ($r.StatusCode -ge 200 -and $r.StatusCode -lt 400)
    } catch {
        return $false
    }
}

function Get-DriverSourceStatus {
    param($Manifest = $null)

    $root = Get-AppRoot
    $driversRoot = Join-Path $root 'Drivers'
    $total = 0
    $localOk = 0

    if ($Manifest -and $Manifest.packages) {
        $total = @($Manifest.packages.PSObject.Properties).Count
    } elseif (Test-Path (Join-Path $root 'driver_packages.json')) {
        try {
            $m = Get-Content (Join-Path $root 'driver_packages.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $total = @($m.packages.PSObject.Properties).Count
        } catch { }
    }

    if (Test-Path $driversRoot) {
        foreach ($dir in (Get-ChildItem $driversRoot -Directory -EA SilentlyContinue)) {
            $hasInf = Get-ChildItem $dir.FullName -Filter '*.inf' -Recurse -EA SilentlyContinue | Select-Object -First 1
            if ($hasInf) { $localOk++ }
        }
    }

    $online = Test-NetworkAvailable
    $mode = if ($localOk -ge [Math]::Max(1, [int]($total * 0.5))) { '混合（本地+在线）' } elseif ($online) { '在线 GitHub Release' } else { '离线（仅本地）' }

    return [PSCustomObject]@{
        SourceLabel   = $mode
        LocalCount    = $localOk
        TotalPackages = $total
        NetworkOk     = $online
        SummaryLine   = ("驱动源: {0} | 本地 {1}/{2} | 网络: {3}" -f $mode, $localOk, $total, $(if ($online) { '可连接' } else { '不可用' }))
    }
}
