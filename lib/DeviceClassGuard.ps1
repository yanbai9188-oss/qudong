# Device class hard gate — block cross-category mismatches (v1.6.4 trust fix)

$script:ClassDenyMap = @{
    'network_wifi' = @('mei', 'chipset', 'serialio', 'thunderbolt', 'storage', 'network_lan', 'bluetooth', 'audio', 'display')
    'network_lan'  = @('mei', 'chipset', 'network_wifi', 'bluetooth', 'audio', 'display', 'serialio')
    'bluetooth'    = @('network_wifi', 'network_lan', 'chipset', 'mei', 'audio', 'display', 'storage')
    'audio'        = @('chipset', 'mei', 'network_lan', 'network_wifi', 'display', 'storage')
    'mei'          = @('network_wifi', 'network_lan', 'bluetooth', 'audio', 'display', 'chipset')
    'chipset'      = @('network_wifi', 'network_lan', 'bluetooth', 'audio', 'display', 'mei')
    'display'      = @('mei', 'chipset', 'network_wifi', 'bluetooth', 'audio', 'storage')
}

function Get-CIODIYDeviceClass {
    param($Device)

    $text = @(
        [string]$Device.Class
        [string]$Device.FriendlyName
        [string]$Device.Name
        [string]$Device.InstanceId
        ($Device.HardwareIds -join ' ')
    ) -join ' '

    if ($text -match '(Wi-Fi|Wireless|WLAN|802\.11|Dual Band Wireless|Net.*802\.11|PCI\\VEN_8086[^\\]*\\DEV_08B[12]|DEV_24FD|DEV_2723|DEV_3165|DEV_8265|DEV_51F0|DEV_7A70)') {
        return 'network_wifi'
    }

    if ($text -match '(Bluetooth|BTHENUM|BTH\\|RFCOMM|VID_8087&PID_07DC|VID_8087&PID_0026|VID_8087&PID_0032)') {
        return 'bluetooth'
    }

    if ($text -match '(Audio|HDAUDIO|Realtek High Definition|Sound|SST|Smart Sound|Display Audio)') {
        return 'audio'
    }

    if ($text -match '(MEI|Management Engine|HECI|PCI\\VEN_8086[^\\]*\\DEV_43E0|DEV_A0EB|DEV_A360|DEV_9D3A)') {
        return 'mei'
    }

    if ($text -match '(Chipset|SMBus|SM Bus|LPC|PCI Express Root|ISA Bridge|PCI\\VEN_8086[^\\]*\\DEV_43A[34]|Serial IO|SerialIO)') {
        if ($text -match 'Serial\s*IO|SerialIO|DEV_43A8|DEV_A0A8|DEV_9A60') { return 'serialio' }
        return 'chipset'
    }

    if ($text -match '(Ethernet|GbE|LAN|10EC&DEV_8168|I219|Realtek PCIe|Net.*Controller)') {
        if ($text -notmatch 'Wireless|Wi-Fi|WLAN|802\.11') { return 'network_lan' }
    }

    if ($text -match '(Display|VGA|NVIDIA|AMD Radeon|Intel\(R\).*Graphics|DEV_9A49|DEV_4680)') {
        return 'display'
    }

    if ($text -match '(USBSTOR\\|Mass Storage|大容量存储|USB 存储|Removable Disk)') {
        return 'usb_storage'
    }

    if ($text -match '(USB.*Controller|xHCI|USB3|DEV_43CB|DEV_9A13)') {
        return 'usb'
    }

    if ($text -match '(RST|VMD|Storage|SCSI|NVMe|DEV_09AB|DEV_467F)') {
        return 'storage'
    }

    return 'unknown'
}

function Get-CIODIYPackageClass {
    param(
        $PackageRaw = $null,
        $Package = $null
    )

    $raw = if ($PackageRaw) { $PackageRaw } elseif ($Package) { $Package } else { $null }
    if (-not $raw) { return 'unknown' }

    if ($raw.deviceClass) { return [string]$raw.deviceClass }
    if ($Package -and $Package.DeviceClass) { return [string]$Package.DeviceClass }

    $cat = if ($raw.category) { [string]$raw.category.ToLowerInvariant() } else { '' }
    $id = if ($raw.id) { [string]$raw.id.ToLowerInvariant() } else { '' }
    $title = if ($raw.title) { [string]$raw.title } elseif ($Package -and $Package.Title) { [string]$Package.Title } else { '' }

    switch -Regex ($cat) {
        '^wifi$'         { return 'network_wifi' }
        '^lan$'          { return 'network_lan' }
        '^bluetooth$'    { return 'bluetooth' }
        '^mei$'          { return 'mei' }
        '^chipset$'      { return 'chipset' }
        '^(audio|media|sst)$' { return 'audio' }
        '^(graphics|display)$' { return 'display' }
        '^serial'        { return 'serialio' }
        '^storage$'      { return 'storage' }
        '^usb'           { return 'usb' }
        '^platform$'     { return 'platform' }
        '^touchpad$'     { return 'input' }
        '^printer$'      { return 'printer' }
    }

    if ($id -match 'wifi|wireless|7260|8260') { return 'network_wifi' }
    if ($id -match 'bluetooth|bt_') { return 'bluetooth' }
    if ($id -match 'mei') { return 'mei' }
    if ($id -match 'chipset|serialio|serial_io') { if ($id -match 'serial') { return 'serialio' }; return 'chipset' }
    if ($id -match 'lan|8168|i219') { return 'network_lan' }
    if ($id -match 'audio|sst|sound') { return 'audio' }
    if ($id -match 'graphics|gpu|nvidia|display') { return 'display' }
    if ($id -match 'usb') { return 'usb' }
    if ($id -match 'rst|storage') { return 'storage' }

    if ($title -match 'WiFi|无线|Wireless|7260|8260|AX|AC') { return 'network_wifi' }
    if ($title -match '蓝牙|Bluetooth') { return 'bluetooth' }
    if ($title -match 'MEI|管理引擎') { return 'mei' }
    if ($title -match 'Chipset|芯片组|SMBus|Serial IO') { if ($title -match 'Serial IO') { return 'serialio' }; return 'chipset' }
    if ($title -match 'Realtek.*LAN|网卡|GbE|8168|I219') { return 'network_lan' }
    if ($title -match 'Audio|音频|SST|Sound') { return 'audio' }
    if ($title -match 'Graphics|显卡|GeForce|Radeon|核显') { return 'display' }

    return 'unknown'
}

function Test-DeviceClassDenied {
    param(
        [string]$DeviceClass,
        [string]$PackageClass
    )

    if ([string]::IsNullOrWhiteSpace($DeviceClass) -or [string]::IsNullOrWhiteSpace($PackageClass)) { return $false }
    if ($DeviceClass -eq 'unknown' -or $PackageClass -eq 'unknown') { return $false }

    $deny = $script:ClassDenyMap[$DeviceClass]
    if (-not $deny) { return $false }
    return ($deny -contains $PackageClass)
}

function Test-DeviceClassCompatible {
    param(
        $Device,
        $PackageRaw = $null,
        $Package = $null
    )

    $deviceClass = Get-CIODIYDeviceClass -Device $Device
    $packageClass = Get-CIODIYPackageClass -PackageRaw $PackageRaw -Package $Package

    if (Test-DeviceClassDenied -DeviceClass $deviceClass -PackageClass $packageClass) {
        return $false
    }

    if ($deviceClass -ne 'unknown' -and $packageClass -ne 'unknown' -and $deviceClass -ne $packageClass) {
        return $false
    }

    return $true
}

function Test-ExactHwidMatch {
    param(
        [Parameter(Mandatory)]$Device,
        [string[]]$PatternIds
    )

    if (-not $PatternIds -or $PatternIds.Count -eq 0) { return $false }
    $score = Get-HwIdMatchScore -DeviceIds $Device.HardwareIds -PatternIds $PatternIds
    return ($score -ge 42)
}

function Test-DevicePackageAllowed {
    param(
        [Parameter(Mandatory)]$Device,
        $PackageRaw = $null,
        $Package = $null,
        [string[]]$MatchHwids = @()
    )

    if (-not (Test-DeviceClassCompatible -Device $Device -PackageRaw $PackageRaw -Package $Package)) {
        return $false
    }

    $deviceClass = Get-CIODIYDeviceClass -Device $Device
    if ($deviceClass -eq 'unknown') {
        $patterns = if ($MatchHwids.Count -gt 0) { $MatchHwids }
                    elseif ($PackageRaw -and $PackageRaw.hwids) { @($PackageRaw.hwids) }
                    elseif ($Package -and $Package._MatchHwids) { @($Package._MatchHwids) }
                    else { @() }
        if (-not (Test-ExactHwidMatch -Device $Device -PatternIds $patterns)) {
            return $false
        }
    }

    return $true
}
