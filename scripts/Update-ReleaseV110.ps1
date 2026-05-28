#requires -Version 5.1
# Bump manifest to release v1.1.0 URLs and append extended driver packages
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$path = Join-Path $root 'driver_packages.json'
$raw = Get-Content $path -Raw -Encoding UTF8
$raw = $raw -replace '/releases/download/v1\.0\.0/', '/releases/download/v1.1.0/'
$m = $raw | ConvertFrom-Json

$m.version = '1.3.0'
$m.release = 'v1.1.0'
$m.updated = (Get-Date -Format 'yyyy-MM-dd')
$m.description = 'CIODIY driver manifest v3 - Win10/Win11, release v1.1.0 unified URLs'

$base = 'https://github.com/yanbai9188-oss/qudong/releases/download/v1.1.0'

$newPackages = @{
    Seed_NVIDIA_DCH = @{
        id = 'nvidia_dch_gpu'
        url = "$base/nvidia_dch_gpu.zip"
        version = '31.0.15.5123'
        sha256 = ''
        category = 'gpu'
        vendor = 'NVIDIA'
        score = 88
        confidence = 'high'
        success_rate = 0.92
        priority = 82
        risk = 'medium'
        signed = $true
        whql = $true
        reboot_required = $true
        installOrder = 38
        verify = 'gpu'
        rollback = $true
        win10_preferred = $true
        os = @('win10', 'win11')
        title = 'NVIDIA GeForce DCH (Catalog WHQL, Win10/11)'
        hwids = @(
            'PCI\VEN_10DE&DEV_1C82', 'PCI\VEN_10DE&DEV_1C83', 'PCI\VEN_10DE&DEV_1B81',
            'PCI\VEN_10DE&DEV_1B84', 'PCI\VEN_10DE&DEV_2484', 'PCI\VEN_10DE&DEV_2487',
            'PCI\VEN_10DE&DEV_2204', 'PCI\VEN_10DE&DEV_2206', 'PCI\VEN_10DE&DEV_2504',
            'PCI\VEN_10DE&DEV_2782', 'PCI\VEN_10DE&DEV_2882', 'PCI\VEN_10DE&DEV_1F02'
        )
    }
    Seed_Synaptics_TouchPad = @{
        id = 'synaptics_touchpad'
        url = "$base/synaptics_touchpad.zip"
        version = '19.5.29.2'
        sha256 = ''
        category = 'input'
        vendor = 'Synaptics'
        score = 85
        confidence = 'high'
        success_rate = 0.90
        priority = 60
        risk = 'low'
        signed = $true
        whql = $true
        reboot_required = $false
        installOrder = 58
        verify = 'enum'
        rollback = $true
        win10_preferred = $true
        os = @('win10', 'win11')
        title = 'Synaptics 触摸板 / ClickPad'
        hwids = @(
            'HID\SYNA1B49', 'HID\SYNA7501', 'HID\SYNA1202', 'ACPI\SYNA1202',
            'ACPI\SYNA3101', 'HID\SYNA3101'
        )
    }
    Seed_ELAN_TouchPad = @{
        id = 'elan_touchpad'
        url = "$base/elan_touchpad.zip"
        version = '18.6.30.2'
        sha256 = ''
        category = 'input'
        vendor = 'ELAN'
        score = 84
        confidence = 'high'
        success_rate = 0.89
        priority = 59
        risk = 'low'
        signed = $true
        whql = $true
        reboot_required = $false
        installOrder = 59
        verify = 'enum'
        rollback = $true
        win10_preferred = $true
        os = @('win10', 'win11')
        title = 'ELAN 精密触摸板 PrecisionTouchPad'
        hwids = @(
            'HID\ELAN1200', 'HID\ELAN0708', 'HID\ELAN0501', 'HID\ELAN1000',
            'ACPI\ELAN1200'
        )
    }
    Seed_HP_Printer_PCL = @{
        id = 'hp_printer_pcl'
        url = "$base/hp_printer_pcl.zip"
        version = '10.0.22621.1'
        sha256 = ''
        category = 'printer'
        vendor = 'HP'
        score = 80
        confidence = 'medium'
        success_rate = 0.87
        priority = 65
        risk = 'low'
        signed = $true
        whql = $true
        reboot_required = $false
        installOrder = 70
        verify = 'enum'
        rollback = $true
        win10_preferred = $true
        os = @('win10', 'win11')
        title = 'HP LaserJet / PCL 通用打印驱动'
        hwids = @(
            'USBPRINT\Hewlett-PackardHP_LaserJet_1020',
            'USBPRINT\Hewlett-PackardHP_LaserJet_Pro',
            'USBPRINT\Hewlett-PackardHP_LaserJet_1018'
        )
    }
    Seed_Canon_Printer = @{
        id = 'canon_printer_ufrii'
        url = "$base/canon_printer_ufrii.zip"
        version = '10.0.22621.1'
        sha256 = ''
        category = 'printer'
        vendor = 'Canon'
        score = 79
        confidence = 'medium'
        success_rate = 0.86
        priority = 71
        risk = 'low'
        signed = $true
        whql = $true
        reboot_required = $false
        installOrder = 71
        verify = 'enum'
        rollback = $true
        win10_preferred = $true
        os = @('win10', 'win11')
        title = 'Canon imageCLASS / UFRII 打印驱动'
        hwids = @(
            'USB\VID_04A9&PID_2676', 'USB\VID_04A9&PID_264D', 'USB\VID_04A9&PID_2774'
        )
    }
}

foreach ($key in $newPackages.Keys) {
    $obj = [PSCustomObject]$newPackages[$key]
    if ($m.packages.PSObject.Properties.Name -contains $key) {
        foreach ($prop in $obj.PSObject.Properties) {
            $m.packages.$key.$($prop.Name) = $prop.Value
        }
    } else {
        $m.packages | Add-Member -MemberType NoteProperty -Name $key -Value $obj -Force
    }
}

($m | ConvertTo-Json -Depth 12) | Set-Content $path -Encoding UTF8
$repo = Join-Path $root 'qudong-repo'
Copy-Item $path (Join-Path $repo 'manifest.json') -Force
Copy-Item $path (Join-Path $repo 'driver_packages.json') -Force

# driver_mirror.json release_base
$mirrorPath = Join-Path $root 'driver_mirror.json'
if (Test-Path $mirrorPath) {
    $mirror = Get-Content $mirrorPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $mirror.release_base = $base
    ($mirror | ConvertTo-Json -Depth 4) | Set-Content $mirrorPath -Encoding UTF8
}

Write-Host "manifest v$($m.version) release=$($m.release) packages=$($m.packages.PSObject.Properties.Count)" -ForegroundColor Green
