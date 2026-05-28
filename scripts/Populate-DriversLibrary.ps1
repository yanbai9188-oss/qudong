# Populate Drivers\ library for CIODIY offline install
#requires -Version 5.1
param(
    [switch]$SkipMirrorZips,
    [switch]$SkipCatalog,
    [string[]]$Packages = @()
)

$ErrorActionPreference = 'Stop'
$AppRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $AppRoot 'engine\DriverEngine.ps1') -AppRoot $AppRoot

$driversRoot = Join-Path $AppRoot 'Drivers'
New-Item -ItemType Directory -Force -Path $driversRoot | Out-Null

$log = { param($m) Write-Host $m }

function Write-Step { param([string]$Msg) Write-Host ("`n==> {0}" -f $Msg) -ForegroundColor Cyan }

function Expand-CabToFolder {
    param(
        [Parameter(Mandatory)][string]$CabPath,
        [Parameter(Mandatory)][string]$DestDir
    )
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    & expand.exe -F:* $CabPath $DestDir | Out-Null
}

function Save-SourceTxt {
    param([string]$Dir, [string[]]$Lines)
    Set-Content -Path (Join-Path $Dir 'source.txt') -Value $Lines -Encoding UTF8
}

# Fallback mirror (works today) until yanbai9188-oss/qudong Release is published
$MirrorBase = 'https://github.com/yanbai5201-netizen/driver-mirror/releases/download/v2026.06.05'

$MirrorZips = @{
    'intel_wifi'        = 'intel_wifi'
    'intel_chipset'     = 'intel_chipset'
    'intel_bluetooth'   = 'intel_bluetooth'
    'intel_mei'         = 'intel_mei'
    'intel_sst'         = 'intel_sst'
    'intel_dtt'         = 'intel_dtt'
    'intel_platform'    = 'intel_platform'
    'intel_serialio'    = 'intel_serialio'
    'intel_rst'         = 'intel_rst'
    'realtek_lan'       = 'realtek_lan'
    'realtek_audio'     = 'realtek_audio'
    'amd_chipset'       = 'amd_chipset'
}

$CatalogItems = @(
    @{
        Folder    = 'Intel_7260_WiFi_16.10.0.5'
        HardwareId = 'PCI\VEN_8086&DEV_08B1'
        Query     = 'Intel Dual Band Wireless-AC 7260'
    },
    @{
        Folder    = 'Intel_7260_Bluetooth_20.100.5.1'
        HardwareId = 'USB\VID_8087&PID_07DC'
        Query     = 'Intel Wireless Bluetooth'
    },
    @{
        Folder    = 'Realtek_LAN_8168'
        HardwareId = 'PCI\VEN_10EC&DEV_8168'
        Query     = 'Realtek PCIe GbE Family Controller'
    },
    @{
        Folder    = 'Intel_DisplayAudio'
        HardwareId = 'HDAUDIO\FUNC_01&VEN_8086&DEV_2812'
        Query     = 'Intel Display Audio'
    }
)

if (-not $SkipMirrorZips) {
    Write-Step 'Download mirror ZIP packages'
    $cache = Join-Path $AppRoot 'Cache'
    New-Item -ItemType Directory -Force -Path $cache | Out-Null

    foreach ($folder in $MirrorZips.Keys) {
        if ($Packages.Count -gt 0 -and ($Packages -notcontains $folder)) { continue }
        $dest = Join-Path $driversRoot $folder
        if ((Test-Path $dest) -and (Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue)) {
            Write-Host "  skip (exists): $folder"
            continue
        }

        $zipName = $MirrorZips[$folder] + '.zip'
        $zipPath = Join-Path $cache $zipName
        $url = "$MirrorBase/$zipName"
        Write-Host "  download: $zipName"
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -TimeoutSec 900
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        Expand-Archive -Path $zipPath -DestinationPath $dest -Force
        Save-SourceTxt -Dir $dest -Lines @("Source: $url", "Folder: $folder", "Synced: $(Get-Date -Format o)")
        Write-Host "  ok: $folder"
    }
}

if (-not $SkipCatalog) {
    Write-Step 'Download Catalog legacy / CIODIY packages'
    foreach ($item in $CatalogItems) {
        if ($Packages.Count -gt 0 -and ($Packages -notcontains $item.Folder)) { continue }
        $dest = Join-Path $driversRoot $item.Folder
        if ((Test-Path $dest) -and @(Get-ChildItem $dest -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue).Count -gt 0) {
            Write-Host "  skip (has INF): $($item.Folder)"
            continue
        }

        Write-Host "  catalog: $($item.Folder) [$($item.HardwareId)]"
        try {
            $downloaded = Download-CatalogDriver -HardwareId $item.HardwareId -DestDir $dest -OnLog $log
            if (-not $downloaded) {
                Write-Host "  WARN catalog failed: $($item.Folder)" -ForegroundColor Yellow
            } else {
                Write-Host "  ok: $($item.Folder)"
            }
        } catch {
            Write-Host "  WARN catalog error: $($item.Folder) - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

Write-Step 'Summary'
Get-ChildItem $driversRoot -Directory | ForEach-Object {
    $infs = @(Get-ChildItem $_.FullName -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue).Count
    $mb = [math]::Round((Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
    Write-Host ("  {0,-35} INF={1} Size={2}MB" -f $_.Name, $infs, $mb)
}

Write-Host "`nDone. Drivers root: $driversRoot" -ForegroundColor Green
