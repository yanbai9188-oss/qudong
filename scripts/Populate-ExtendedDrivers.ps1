#requires -Version 5.1
# Download NVIDIA / touchpad / printer drivers via Microsoft Update Catalog
param(
    [string[]]$Only = @(),
    [switch]$Force
)

if ($Only.Count -eq 1 -and $Only[0] -match ',') {
    $Only = $Only[0].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

$ErrorActionPreference = 'Stop'
$AppRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $AppRoot 'engine\DriverEngine.ps1') -AppRoot $AppRoot

$driversRoot = Join-Path $AppRoot 'Drivers'
New-Item -ItemType Directory -Force -Path $driversRoot | Out-Null
$log = { param($m) Write-Host $m }

$Catalog = @(
    @{
        Id         = 'synaptics_touchpad'
        Folder     = 'synaptics_touchpad'
        HardwareId = 'HID\SYNA1B49'
        Title      = 'Synaptics SMBus TouchPad'
        Keywords   = @('Synaptics ClickPad Driver', 'Synaptics SMBus Driver')
    },
    @{
        Id         = 'synaptics_touchpad_alt'
        Folder     = 'synaptics_touchpad'
        HardwareId = 'ACPI\SYNA1202'
        Title      = 'Synaptics ACPI touchpad (alternate HWID)'
        Keywords   = @('Synaptics ClickPad Driver')
    },
    @{
        Id         = 'elan_touchpad'
        Folder     = 'elan_touchpad'
        HardwareId = 'HID\ELAN1200'
        Title      = 'ELAN PrecisionTouchPad'
    },
    @{
        Id         = 'elan_touchpad_alt'
        Folder     = 'elan_touchpad'
        HardwareId = 'HID\ELAN0708'
        Title      = 'ELAN touchpad (alternate HWID)'
    },
    @{
        Id         = 'hp_printer_pcl'
        Folder     = 'hp_printer_pcl'
        HardwareId = 'USBPRINT\Hewlett-PackardHP_LaserJet_1020'
        Title      = 'HP LaserJet 1020 class PCL printer'
        Keywords   = @('HP Universal Printing PCL 6', 'HP LaserJet Pro P1102')
    },
    @{
        Id         = 'canon_printer_ufrii'
        Folder     = 'canon_printer_ufrii'
        HardwareId = 'USB\VID_04A9&PID_2676'
        Title      = 'Canon imageCLASS / UFRII USB printer'
        Keywords   = @('Canon Generic Plus UFR II', 'Canon UFR II Printer Driver')
    },
    @{
        Id         = 'nvidia_dch_gpu'
        Folder     = 'nvidia_dch_gpu'
        HardwareId = 'PCI\VEN_10DE&DEV_1C82'
        Title      = 'NVIDIA GeForce GTX 1050 Ti (DCH, Catalog WHQL)'
    },
    @{
        Id         = 'nvidia_dch_gpu_rtx'
        Folder     = 'nvidia_dch_gpu'
        HardwareId = 'PCI\VEN_10DE&DEV_2484'
        Title      = 'NVIDIA RTX 3070 fallback HWID (same folder as DCH pack)'
    }
)

Write-Host '=== Populate extended drivers (Catalog) ===' -ForegroundColor Cyan
$doneFolders = @{}

foreach ($item in $Catalog) {
    if ($Only.Count -gt 0 -and ($Only -notcontains $item.Id)) { continue }
    if ($doneFolders.ContainsKey($item.Folder) -and -not $Force) { continue }

    $dest = Join-Path $driversRoot $item.Folder
    if (-not $Force -and (Test-Path $dest) -and @(Get-ChildItem $dest -Filter '*.inf' -Recurse -EA SilentlyContinue).Count -gt 0) {
        $mb = [math]::Round((Get-ChildItem $dest -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
        Write-Host "  skip (exists): $($item.Folder) (${mb}MB)"
        $doneFolders[$item.Folder] = $true
        continue
    }

    Write-Host "  catalog: $($item.Title)"
    Write-Host "    HWID: $($item.HardwareId)"
    try {
        if ($Force -and (Test-Path $dest)) { Remove-Item $dest -Recurse -Force -EA SilentlyContinue }
        $kw = @()
        if ($item.Keywords) { $kw = @($item.Keywords) }
        $ok = Download-CatalogDriver -HardwareId $item.HardwareId -DestDir $dest -OnLog $log `
            -KeywordFallback $kw
        if (-not $ok) {
            Write-Host '  WARN: no catalog match' -ForegroundColor Yellow
            continue
        }
        $infs = @(Get-ChildItem $dest -Filter '*.inf' -Recurse -EA SilentlyContinue).Count
        $mb = [math]::Round((Get-ChildItem $dest -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
        Write-Host "  ok: $($item.Folder) infs=$infs (${mb}MB)" -ForegroundColor Green
        $doneFolders[$item.Folder] = $true
    } catch {
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nSummary:" -ForegroundColor Cyan
@('nvidia_dch_gpu', 'synaptics_touchpad', 'elan_touchpad', 'hp_printer_pcl', 'canon_printer_ufrii') | ForEach-Object {
    $p = Join-Path $driversRoot $_
    if (-not (Test-Path $p)) {
        Write-Host "  $_ : (missing)"
        return
    }
    $infs = @(Get-ChildItem $p -Filter '*.inf' -Recurse -EA SilentlyContinue).Count
    $mb = [math]::Round((Get-ChildItem $p -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
    Write-Host ("  {0,-22} {1,3} inf  {2,7} MB" -f $_, $infs, $mb)
}
