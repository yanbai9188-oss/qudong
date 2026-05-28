# Unified device display names (v1.6.6)

function Format-CIODIYDeviceDisplayName {
    param(
        [string]$Name,
        $Device = $null,
        $Package = $null
    )

    $n = if ($Name) { [string]$Name.Trim() } else { '' }

    switch -Regex ($n) {
        '(?i)Intel\(R\).*Dual Band Wireless.*7260' { return 'Intel 无线网卡 AC7260' }
        '(?i)Intel\(R\).*Wireless.*7260'            { return 'Intel 无线网卡 AC7260' }
        '(?i)Intel\(R\).*Bluetooth.*7260'           { return 'Intel 蓝牙 7260' }
        '(?i)High Definition Audio'                { return '高清音频设备' }
        '(?i)Mass Storage|大容量存储'                 { return 'USB 存储设备' }
        '(?i)SM Bus|SMBus|SM 总线'                  { return 'Intel 芯片组控制器' }
        default { }
    }

    if ($Device -and $Device.PackageGroupCount -gt 1) {
        return 'Intel 芯片组设备'
    }

    return $n
}
