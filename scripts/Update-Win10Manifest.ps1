#requires -Version 5.1
# Append Win10 common packages to driver_packages.json
$ErrorActionPreference = 'Stop'
$path = Join-Path (Split-Path $PSScriptRoot -Parent) 'driver_packages.json'
$m = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
$m.version = '1.2.0'
$m.updated = (Get-Date -Format 'yyyy-MM-dd')

$base = 'https://github.com/yanbai9188-oss/qudong/releases/download/v1.1.0'
$newPackages = @{
    Seed_Intel_USB3 = @{
        id = 'intel_usb3'
        url = "$base/intel_usb3.zip"
        version = '10.1.23.5'
        sha256 = ''
        category = 'usb'
        vendor = 'Intel'
        score = 88
        confidence = 'high'
        success_rate = 0.93
        priority = 88
        risk = 'low'
        signed = $true
        whql = $true
        reboot_required = $false
        installOrder = 15
        verify = 'enum'
        rollback = $true
        win10_preferred = $true
        os = @('win10', 'win11')
        title = 'Intel USB 3.0 xHCI / 芯片组 USB (Win10 批量)'
        hwids = @(
            'PCI\VEN_8086&DEV_1E31', 'PCI\VEN_8086&DEV_8CB1', 'PCI\VEN_8086&DEV_9DED',
            'PCI\VEN_8086&DEV_A87E', 'PCI\VEN_8086&DEV_43ED', 'PCI\VEN_8086&DEV_06ED',
            'PCI\VEN_8086&DEV_1E2D', 'PCI\VEN_8086&DEV_8C31', 'PCI\VEN_8086&DEV_9C31'
        )
    }
    Seed_Intel_LAN_I219 = @{
        id = 'intel_lan_i219'
        url = "$base/intel_lan_i219.zip"
        version = '12.19.2.45'
        sha256 = ''
        category = 'lan'
        vendor = 'Intel'
        score = 89
        confidence = 'high'
        success_rate = 0.94
        priority = 92
        risk = 'low'
        signed = $true
        whql = $true
        reboot_required = $false
        installOrder = 32
        verify = 'net'
        rollback = $true
        win10_preferred = $true
        os = @('win10', 'win11')
        title = 'Intel I219-V/LM 板载千兆网卡'
        hwids = @(
            'PCI\VEN_8086&DEV_15B8', 'PCI\VEN_8086&DEV_15D8', 'PCI\VEN_8086&DEV_15F4',
            'PCI\VEN_8086&DEV_15BD', 'PCI\VEN_8086&DEV_15BE', 'PCI\VEN_8086&DEV_15BB'
        )
    }
    Seed_Realtek_CardReader = @{
        id = 'realtek_cardreader'
        url = "$base/realtek_cardreader.zip"
        version = '10.0.22000.31274'
        sha256 = ''
        category = 'storage'
        vendor = 'Realtek'
        score = 86
        confidence = 'high'
        success_rate = 0.91
        priority = 75
        risk = 'low'
        signed = $true
        whql = $true
        reboot_required = $false
        installOrder = 55
        verify = 'enum'
        rollback = $true
        win10_preferred = $true
        os = @('win10', 'win11')
        title = 'Realtek 读卡器 RTS52xx'
        hwids = @(
            'PCI\VEN_10EC&DEV_5229', 'PCI\VEN_10EC&DEV_522A', 'PCI\VEN_10EC&DEV_5249',
            'PCI\VEN_10EC&DEV_5289', 'PCI\VEN_10EC&DEV_5209'
        )
    }
    Seed_Intel_WiFi_8260 = @{
        id = 'intel_wifi_8260'
        url = "$base/intel_wifi_8260.zip"
        version = '22.40.0.7'
        sha256 = ''
        category = 'wifi'
        vendor = 'Intel'
        score = 90
        confidence = 'high'
        success_rate = 0.96
        priority = 94
        risk = 'low'
        signed = $true
        whql = $true
        reboot_required = $false
        installOrder = 28
        verify = 'wifi'
        rollback = $true
        win10_preferred = $true
        depends = @('intel_mei')
        conflicts = @('intel_wifi', 'intel_wifi_7260')
        os = @('win10', 'win11')
        title = 'Intel WiFi AC 8260/8265 (Win10 常见)'
        hwids = @(
            'PCI\VEN_8086&DEV_24FD', 'PCI\VEN_8086&DEV_24F3', 'PCI\VEN_8086&DEV_24F4',
            'PCI\VEN_8086&DEV_24FB'
        )
    }
}

foreach ($key in $newPackages.Keys) {
    $obj = [PSCustomObject]$newPackages[$key]
    $m.packages | Add-Member -MemberType NoteProperty -Name $key -Value $obj -Force
}

($m | ConvertTo-Json -Depth 12) | Set-Content $path -Encoding UTF8
$repo = Join-Path (Split-Path $PSScriptRoot -Parent) 'qudong-repo'
Copy-Item $path (Join-Path $repo 'manifest.json') -Force
Copy-Item $path (Join-Path $repo 'driver_packages.json') -Force
Write-Host "manifest v$($m.version) packages=$($m.packages.PSObject.Properties.Count)"
