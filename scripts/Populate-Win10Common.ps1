#requires -Version 5.1
# Download Win10 common drivers via Microsoft Update Catalog
param(
    [string[]]$Only = @()
)

$ErrorActionPreference = 'Stop'
$AppRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $AppRoot 'engine\DriverEngine.ps1') -AppRoot $AppRoot

$driversRoot = Join-Path $AppRoot 'Drivers'
New-Item -ItemType Directory -Force -Path $driversRoot | Out-Null
$log = { param($m) Write-Host $m }

$Win10Catalog = @(
    @{
        Id         = 'intel_usb3'
        Folder     = 'intel_usb3'
        HardwareId = 'PCI\VEN_8086&DEV_1E31'
        Title      = 'Intel USB 3.0 eXtensible Host Controller (7th gen+)'
    },
    @{
        Id         = 'intel_usb3_legacy'
        Folder     = 'intel_usb3_legacy'
        HardwareId = 'PCI\VEN_8086&DEV_8C31'
        Title      = 'Intel USB 3.0 xHCI (4th-6th gen)'
    },
    @{
        Id         = 'intel_lan_i219'
        Folder     = 'intel_lan_i219'
        HardwareId = 'PCI\VEN_8086&DEV_15B8'
        Title      = 'Intel Ethernet Connection I219-V/LM'
    },
    @{
        Id         = 'realtek_cardreader'
        Folder     = 'realtek_cardreader'
        HardwareId = 'PCI\VEN_10EC&DEV_5229'
        Title      = 'Realtek PCIe card reader (RTS5229)'
    },
    @{
        Id         = 'intel_wifi_8260'
        Folder     = 'intel_wifi_8260'
        HardwareId = 'PCI\VEN_8086&DEV_24FD'
        Title      = 'Intel Wireless-AC 8260/8265'
    }
)

Write-Host '=== Populate Win10 common drivers (Catalog) ===' -ForegroundColor Cyan
foreach ($item in $Win10Catalog) {
    if ($Only.Count -gt 0 -and ($Only -notcontains $item.Id)) { continue }

    $dest = Join-Path $driversRoot $item.Folder
    if ((Test-Path $dest) -and @(Get-ChildItem $dest -Filter '*.inf' -Recurse -EA SilentlyContinue).Count -gt 0) {
        $mb = [math]::Round((Get-ChildItem $dest -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
        Write-Host "  skip (exists): $($item.Folder) (${mb}MB)"
        continue
    }

    Write-Host "  catalog: $($item.Title)"
    Write-Host "    HWID: $($item.HardwareId)"
    try {
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force -EA SilentlyContinue }
        $ok = Download-CatalogDriver -HardwareId $item.HardwareId -DestDir $dest -OnLog $log
        if (-not $ok) {
            Write-Host "  WARN: no catalog match" -ForegroundColor Yellow
            continue
        }
        $mb = [math]::Round((Get-ChildItem $dest -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
        if ($mb -gt 500) {
            Write-Host "  WARN: package large (${mb}MB), keeping for local use" -ForegroundColor Yellow
        }
        Write-Host "  ok: $($item.Folder) (${mb}MB)" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nSummary:" -ForegroundColor Cyan
Get-ChildItem $driversRoot -Directory | Where-Object { $_.Name -match 'usb3|i219|cardreader|8260' } | ForEach-Object {
    $infs = @(Get-ChildItem $_.FullName -Filter '*.inf' -Recurse -EA SilentlyContinue).Count
    $mb = [math]::Round((Get-ChildItem $_.FullName -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
    Write-Host ("  {0,-25} INF={1} {2}MB" -f $_.Name, $infs, $mb)
}
