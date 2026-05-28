# Add all missing GitHub Release v1.1.0 packages to driver_packages.json
# then push the updated manifest to GitHub as both manifest.json and driver_packages.json

[Console]::OutputEncoding = [Text.Encoding]::UTF8
$utf8 = [Text.Encoding]::UTF8

$tok = $env:GITHUB_TOKEN
if (-not $tok) {
    $tokLine = ("protocol=https`nhost=github.com`n`n" | git credential fill) |
               Where-Object { $_ -like 'password=*' }
    $tok = $tokLine -replace 'password=',''
}
$hdrs = @{ Authorization = "token $tok"; Accept = 'application/vnd.github+json' }
$repo = 'yanbai9188-oss/qudong'
$base = 'https://github.com/yanbai9188-oss/qudong/releases/download/v1.1.0'

$root = Split-Path $PSScriptRoot -Parent
$mfPath = Join-Path $root 'driver_packages.json'
$mf = Get-Content $mfPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ── New packages to add ────────────────────────────────────────────────────────
$newPkgs = [ordered]@{

    'Seed_Intel_Chipset' = [ordered]@{
        id = 'intel_chipset'; title = 'Intel Chipset INF（全平台通用）'
        url = "$base/intel_chipset.zip"; version = '10.1.23.5'; category = 'chipset'
        vendor = 'Intel'; priority = 99; installOrder = 1; risk = 'low'
        signed = $true; whql = $true; reboot_required = $false; rollback = $false
        confidence = 'high'; score = 95; success_rate = 0.98
        os = @('win10','win11'); deviceClass = 'chipset'
        hwids = @(
            'PCI\\VEN_8086&DEV_A0A4','PCI\\VEN_8086&DEV_9D55','PCI\\VEN_8086&DEV_9DA4',
            'PCI\\VEN_8086&DEV_02A4','PCI\\VEN_8086&DEV_43A4','PCI\\VEN_8086&DEV_4DA4',
            'PCI\\VEN_8086&DEV_7AA4','PCI\\VEN_8086&DEV_7A04','PCI\\VEN_8086&DEV_51A4',
            'PCI\\VEN_8086&DEV_54A4','PCI\\VEN_8086&DEV_4641')
    }

    'Seed_Intel_MEI' = [ordered]@{
        id = 'intel_mei'; title = 'Intel 管理引擎 MEI'
        url = "$base/intel_mei.zip"; version = '2317.5.6.0'; category = 'chipset'
        vendor = 'Intel'; priority = 90; installOrder = 5; risk = 'low'
        signed = $true; whql = $true; reboot_required = $false; rollback = $false
        confidence = 'high'; score = 90; success_rate = 0.97
        os = @('win10','win11'); deviceClass = 'chipset'
        hwids = @(
            'PCI\\VEN_8086&DEV_9D3A','PCI\\VEN_8086&DEV_9DE0','PCI\\VEN_8086&DEV_9DF9',
            'PCI\\VEN_8086&DEV_02E0','PCI\\VEN_8086&DEV_43E0','PCI\\VEN_8086&DEV_4DE0',
            'PCI\\VEN_8086&DEV_7AE8','PCI\\VEN_8086&DEV_7AE0','PCI\\VEN_8086&DEV_51E0',
            'PCI\\VEN_8086&DEV_A0E0','PCI\\VEN_8086&DEV_54E0','PCI\\VEN_8086&DEV_7F70')
    }

    'Seed_Intel_SerialIO' = [ordered]@{
        id = 'intel_serialio'; title = 'Intel Serial IO'
        url = "$base/intel_serialio.zip"; version = '30.100.2321.8'; category = 'chipset'
        vendor = 'Intel'; priority = 85; installOrder = 8; risk = 'low'
        signed = $true; whql = $true; reboot_required = $false; rollback = $false
        confidence = 'high'; score = 85; success_rate = 0.97
        os = @('win10','win11'); deviceClass = 'chipset'
        hwids = @(
            'PCI\\VEN_8086&DEV_9D60','PCI\\VEN_8086&DEV_9D61','PCI\\VEN_8086&DEV_9D62',
            'PCI\\VEN_8086&DEV_9DE8','PCI\\VEN_8086&DEV_9DE9','PCI\\VEN_8086&DEV_9DEA',
            'PCI\\VEN_8086&DEV_02E8','PCI\\VEN_8086&DEV_02E9','PCI\\VEN_8086&DEV_02EA',
            'PCI\\VEN_8086&DEV_A0E8','PCI\\VEN_8086&DEV_A0C6','PCI\\VEN_8086&DEV_43E8')
    }

    'Seed_Intel_RST' = [ordered]@{
        id = 'intel_rst'; title = 'Intel RST/VMD 快速存储'
        url = "$base/intel_rst.zip"; version = '19.5.1.1040'; category = 'storage'
        vendor = 'Intel'; priority = 80; installOrder = 15; risk = 'low'
        signed = $true; whql = $true; reboot_required = $false; rollback = $true
        confidence = 'high'; score = 85; success_rate = 0.95
        os = @('win10','win11'); deviceClass = 'storage'
        hwids = @(
            'PCI\\VEN_8086&DEV_9D03','PCI\\VEN_8086&DEV_9D72','PCI\\VEN_8086&DEV_9A0B',
            'PCI\\VEN_8086&DEV_9AF4','PCI\\VEN_8086&DEV_02D3','PCI\\VEN_8086&DEV_43CF',
            'PCI\\VEN_8086&DEV_282A','PCI\\VEN_8086&DEV_2826','PCI\\VEN_8086&DEV_467F',
            'PCI\\VEN_8086&DEV_7AE2')
    }

    'Seed_Intel_DTT' = [ordered]@{
        id = 'intel_dtt'; title = 'Intel DTT / DPTF 动态调优'
        url = "$base/intel_dtt.zip"; version = '9.0.10400.16590'; category = 'chipset'
        vendor = 'Intel'; priority = 70; installOrder = 20; risk = 'low'
        signed = $true; whql = $true; reboot_required = $false; rollback = $false
        confidence = 'medium'; score = 75; success_rate = 0.93
        os = @('win10','win11'); deviceClass = 'chipset'
        hwids = @(
            'ACPI\\INT3400','ACPI\\INTC1040','ACPI\\INTC1042','ACPI\\INTC10A0',
            'ACPI\\INT3407','ACPI\\INT3530','ACPI\\INTC1099')
    }

    'Seed_Intel_Platform' = [ordered]@{
        id = 'intel_platform'; title = 'Intel 平台组件 (ICLS/DAL/ME WMI)'
        url = "$base/intel_platform.zip"; version = '2317.5.6.0'; category = 'chipset'
        vendor = 'Intel'; priority = 65; installOrder = 22; risk = 'low'
        signed = $true; whql = $true; reboot_required = $false; rollback = $false
        confidence = 'medium'; score = 70; success_rate = 0.92
        os = @('win10','win11'); deviceClass = 'chipset'
        hwids = @(
            'PCI\\VEN_8086&DEV_9D98','PCI\\VEN_8086&DEV_9DF9',
            'ACPI\\INT33FE','ACPI\\INT3420')
    }

    'Seed_Intel_USB3' = [ordered]@{
        id = 'intel_usb3'; title = 'Intel USB 3.0 xHCI / 芯片组 USB (Win10 批量)'
        url = "$base/intel_usb3.zip"; version = '5.0.4.43'; category = 'usb'
        vendor = 'Intel'; priority = 88; installOrder = 15; risk = 'low'
        signed = $true; whql = $true; reboot_required = $false; rollback = $true
        confidence = 'high'; score = 88; success_rate = 0.93
        os = @('win10','win11'); deviceClass = 'usb'
        hwids = @(
            'PCI\\VEN_8086&DEV_9D2F','PCI\\VEN_8086&DEV_A2AF','PCI\\VEN_8086&DEV_A36D',
            'PCI\\VEN_8086&DEV_02ED','PCI\\VEN_8086&DEV_43ED','PCI\\VEN_8086&DEV_9A13',
            'PCI\\VEN_8086&DEV_A0ED','PCI\\VEN_8086&DEV_51ED','PCI\\VEN_8086&DEV_4DED')
    }

    'Seed_Intel_Bluetooth' = [ordered]@{
        id = 'intel_bluetooth'; title = 'Intel 蓝牙'
        url = "$base/intel_bluetooth.zip"; version = '23.60.0.3'; category = 'bluetooth'
        vendor = 'Intel'; priority = 92; installOrder = 26; risk = 'low'
        signed = $true; whql = $true; reboot_required = $false; rollback = $true
        confidence = 'high'; score = 93; success_rate = 0.96
        os = @('win10','win11'); deviceClass = 'bluetooth'
        hwids = @(
            'USB\\VID_8087&PID_0029','USB\\VID_8087&PID_0026','USB\\VID_8087&PID_0032',
            'USB\\VID_8087&PID_0033','USB\\VID_8087&PID_0025','USB\\VID_8087&PID_0ABA',
            'USB\\VID_8087&PID_0034','USB\\VID_8087&PID_0035')
    }

    'Seed_Intel_Bluetooth_7260' = [ordered]@{
        id = 'intel_bluetooth_7260'; title = 'Intel Bluetooth 7260 (Legacy)'
        url = "$base/intel_bluetooth_7260.zip"; version = '20.60.1.3'; category = 'bluetooth'
        vendor = 'Intel'; priority = 75; installOrder = 27; risk = 'low'
        signed = $true; whql = $true; reboot_required = $false; rollback = $true
        confidence = 'high'; score = 82; success_rate = 0.94
        os = @('win10'); deviceClass = 'bluetooth'
        conflicts = @('intel_bluetooth')
        hwids = @(
            'USB\\VID_8087&PID_07DC','USB\\VID_8087&PID_0A2A','USB\\VID_8087&PID_0A2B',
            'USB\\VID_8087&PID_0AA7')
    }

    'Seed_Intel_DisplayAudio' = [ordered]@{
        id = 'intel_display_audio'; title = 'Intel Display Audio（含核显完整包，约 1.2GB）'
        url = "$base/intel_display_audio.zip"; version = '101.2403'; category = 'audio'
        vendor = 'Intel'; priority = 72; installOrder = 42; risk = 'low'
        signed = $true; whql = $true; reboot_required = $true; rollback = $true
        confidence = 'high'; score = 80; success_rate = 0.90
        os = @('win10','win11'); deviceClass = 'audio'
        conflicts = @('intel_sst')
        hwids = @(
            'INTELAUDIO\\FUNC_01&VEN_8086&DEV_280D','INTELAUDIO\\FUNC_01&VEN_8086&DEV_280B',
            'INTELAUDIO\\FUNC_01&VEN_8086&DEV_2816','INTELAUDIO\\FUNC_01&VEN_8086&DEV_2809',
            'INTELAUDIO\\FUNC_01&VEN_8086&DEV_2812','INTELAUDIO\\FUNC_01&VEN_8086&DEV_2815')
    }

    'Seed_AMD_Chipset' = [ordered]@{
        id = 'amd_chipset'; title = 'AMD Ryzen Chipset'
        url = "$base/amd_chipset.zip"; version = '5.12.0.34'; category = 'chipset'
        vendor = 'AMD'; priority = 99; installOrder = 2; risk = 'low'
        signed = $true; whql = $true; reboot_required = $false; rollback = $false
        confidence = 'high'; score = 95; success_rate = 0.97
        os = @('win10','win11'); deviceClass = 'chipset'
        hwids = @(
            'PCI\\VEN_1022&DEV_790B','PCI\\VEN_1022&DEV_7901','PCI\\VEN_1022&DEV_7902',
            'PCI\\VEN_1022&DEV_43B4','PCI\\VEN_1022&DEV_43B9','PCI\\VEN_1022&DEV_43BB',
            'PCI\\VEN_1022&DEV_43C6','PCI\\VEN_1022&DEV_43C8','PCI\\VEN_1022&DEV_43D0',
            'PCI\\VEN_1022&DEV_1630','PCI\\VEN_1022&DEV_1639','PCI\\VEN_1022&DEV_164F')
    }

    'Seed_Realtek_CardReader' = [ordered]@{
        id = 'realtek_cardreader'; title = 'Realtek 读卡器 RTS52xx'
        url = "$base/realtek_cardreader.zip"; version = '10.0.22621.31306'; category = 'usb'
        vendor = 'Realtek'; priority = 70; installOrder = 55; risk = 'low'
        signed = $true; whql = $true; reboot_required = $false; rollback = $false
        confidence = 'high'; score = 78; success_rate = 0.92
        os = @('win10','win11'); deviceClass = 'usb'
        hwids = @(
            'USB\\VID_0BDA&PID_0129','USB\\VID_0BDA&PID_0139','USB\\VID_0BDA&PID_0159',
            'USB\\VID_0BDA&PID_0169','USB\\VID_0BDA&PID_0186','USB\\VID_0BDA&PID_0307',
            'PCI\\VEN_10EC&DEV_5227','PCI\\VEN_10EC&DEV_522A','PCI\\VEN_10EC&DEV_5229',
            'PCI\\VEN_10EC&DEV_525A')
    }

    'Seed_Synaptics_TouchPad' = [ordered]@{
        id = 'synaptics_touchpad'; title = 'Synaptics 触摸板 / ClickPad'
        url = "$base/synaptics_touchpad.zip"; version = '19.5.29.2'; category = 'hid'
        vendor = 'Synaptics'; priority = 80; installOrder = 60; risk = 'low'
        signed = $true; whql = $true; reboot_required = $false; rollback = $true
        confidence = 'high'; win10_preferred = $true
        sha256 = '53a03be436e3c564335a3ea4d0978c320e24f8f7b06cf61e42fbe2f4aa441da6'
        verify = 'enum'; success_rate = 0.95; score = 88
        os = @('win10','win11'); deviceClass = 'hid'
        hwids = @(
            'HID\\SYNA1B49','HID\\SYNA7501','HID\\SYNA1202','ACPI\\SYN1202',
            'HID\\SYNA2393','HID\\SYNA2B28','ACPI\\SYN2B28',
            'HID\\MSFT0007&Col01','HID\\SYN0000:00 06CB:7F9F')
    }

    'Seed_ELAN_TouchPad' = [ordered]@{
        id = 'elan_touchpad'; title = 'ELAN 精密触摸板 PrecisionTouchPad'
        url = "$base/elan_touchpad.zip"; version = '16.2.12.1'; category = 'hid'
        vendor = 'ELAN'; priority = 80; installOrder = 61; risk = 'low'
        signed = $true; whql = $true; reboot_required = $false; rollback = $true
        confidence = 'high'; success_rate = 0.94; score = 85
        os = @('win10','win11'); deviceClass = 'hid'
        hwids = @(
            'ACPI\\ELAN0501','ACPI\\ELAN0621','ACPI\\ELAN1000','ACPI\\ELAN1200',
            'ACPI\\ELAN1300','HID\\ELAN_ETP0700','ACPI\\ELAN0001',
            'HID\\ELAN1200:00 04F3:3063','HID\\ELAN1200:00 04F3:30A9')
    }

    'Seed_HP_Printer_PCL' = [ordered]@{
        id = 'hp_printer_pcl'; title = 'HP LaserJet / PCL 通用打印驱动'
        url = "$base/hp_printer_pcl.zip"; version = '61.286.1.26163'; category = 'printer'
        vendor = 'HP'; priority = 65; installOrder = 70; risk = 'low'
        signed = $true; whql = $true; reboot_required = $false; rollback = $true
        confidence = 'medium'; success_rate = 0.87; score = 80
        os = @('win10','win11'); deviceClass = 'printer'
        hwids = @(
            'USBPRINT\\HewlettPackardHP_LaserJet_1020',
            'USBPRINT\\HewlettPackardHP_LaserJet_Pro',
            'USBPRINT\\HewlettPackardHP_LaserJet_1018')
    }

    'Seed_Canon_Printer' = [ordered]@{
        id = 'canon_printer_ufrii'; title = 'Canon imageCLASS / UFRII 打印驱动'
        url = "$base/canon_printer_ufrii.zip"; version = '3.90'; category = 'printer'
        vendor = 'Canon'; priority = 63; installOrder = 71; risk = 'low'
        signed = $true; whql = $true; reboot_required = $false; rollback = $true
        confidence = 'medium'; success_rate = 0.88; score = 78
        os = @('win10','win11'); deviceClass = 'printer'
        hwids = @(
            'USBPRINT\\CanonCanon_LBP2900','USBPRINT\\CanonMF3010',
            'USBPRINT\\CanonimageCLASS_MF','USBPRINT\\CanonLBP')
    }
}

# ── Merge into existing manifest ───────────────────────────────────────────────
$added = 0
foreach ($key in $newPkgs.Keys) {
    if ($mf.packages.PSObject.Properties[$key]) {
        [Console]::WriteLine("SKIP (already exists): $key")
        continue
    }
    # Convert the hashtable to a PSCustomObject and add it
    $obj = [PSCustomObject]$newPkgs[$key]
    $mf.packages | Add-Member -NotePropertyName $key -NotePropertyValue $obj -Force
    [Console]::WriteLine("ADDED: $key")
    $added++
}

# Update version and date
$mf.version = '1.7.0'
$mf.updated = (Get-Date -Format 'yyyy-MM-dd')
$mf.description = 'Yanbai Driver manifest v1.7 - full 31-package coverage'

[Console]::WriteLine("Added $added packages. New total: $($mf.packages.PSObject.Properties.Count)")

# Write local file
$mf | ConvertTo-Json -Depth 20 | Set-Content $mfPath -Encoding UTF8
[Console]::WriteLine("Saved: $mfPath")

# ── Push to GitHub as manifest.json ───────────────────────────────────────────
function Push-GitHubFile([string]$filename, [string]$content, [string]$commitMsg) {
    $fileMeta = try {
        Invoke-RestMethod "https://api.github.com/repos/$repo/contents/$filename" -Headers $hdrs
    } catch { $null }
    $sha = if ($fileMeta) { $fileMeta.sha } else { $null }

    $body = [PSCustomObject]@{
        message = $commitMsg
        content = [Convert]::ToBase64String($utf8.GetBytes($content))
        branch  = 'main'
    }
    if ($sha) { $body | Add-Member -NotePropertyName sha -NotePropertyValue $sha -Force }

    $bodyBytes = $utf8.GetBytes(($body | ConvertTo-Json -Compress))
    $r = Invoke-RestMethod "https://api.github.com/repos/$repo/contents/$filename" `
        -Method PUT -Headers $hdrs -Body $bodyBytes -ContentType 'application/json; charset=utf-8'
    [Console]::WriteLine("Pushed $filename -> commit $($r.commit.sha.Substring(0,8))")
}

$jsonContent = $mf | ConvertTo-Json -Depth 20
Push-GitHubFile 'manifest.json' $jsonContent 'manifest: add 16 missing packages, bump to v1.7.0'
Push-GitHubFile 'driver_packages.json' $jsonContent 'driver_packages: sync with manifest v1.7.0'

[Console]::WriteLine('Done.')
