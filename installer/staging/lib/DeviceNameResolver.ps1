# Smart device display names (v1.6.5)

function Get-DeviceClassLabel {
    param([string]$Class)

    switch ($Class) {
        'bluetooth'    { return '蓝牙' }
        'network_wifi' { return '无线网卡' }
        'network_lan'  { return '有线网卡' }
        'audio'        { return '音频' }
        'mei'          { return '管理引擎' }
        'chipset'      { return '芯片组' }
        'display'      { return '显卡' }
        'usb'          { return 'USB' }
        'storage'      { return '存储' }
        'serialio'     { return '串口 IO' }
        'input'        { return '输入设备' }
        'printer'      { return '打印机' }
        default        { return '' }
    }
}

function Resolve-CIODIYDeviceName {
    param(
        $Device,
        $Package = $null
    )

    if (-not $Device) { return '未知设备' }

    $raw = if ($Device.FriendlyName) { [string]$Device.FriendlyName } else { [string]$Device.Name }
    $base = ConvertTo-CIODIYUserText -Text $raw
    $text = @($base, [string]$Device.Class, [string]$Device.InstanceId, ($Device.HardwareIds -join ' ')) -join ' '
    $devClass = if ($Device.DeviceClass) { [string]$Device.DeviceClass } else { Get-CIODIYDeviceClass -Device $Device }
    $pkgClass = if ($Package) { Get-CIODIYPackageClass -Package $Package } else { '' }

    if ($text -match 'SM Bus|SM 总线|SMBus') {
        $base = 'Intel 芯片组控制器'
    }
    elseif ($text -match '(?i)High Definition Audio|HDAUDIO|高清音频') {
        $base = '高清音频设备'
    }
    elseif ($text -match '(?i)USB.*Mass Storage|USB 大容量存储|USBSTOR') {
        $base = 'USB 存储设备'
    }
    elseif ($text -match '(?i)PCI 设备|PCI Device') {
        if ($pkgClass -eq 'mei' -or $Package.Title -match 'MEI|管理引擎') {
            $base = 'Intel 管理引擎接口（MEI）'
        }
        elseif ($pkgClass -eq 'chipset' -or $Package.Title -match 'Chipset|芯片组') {
            $base = 'Intel 芯片组设备'
        }
        else {
            $base = 'PCI 扩展设备'
        }
    }
    elseif ($base -eq '未知设备' -or [string]::IsNullOrWhiteSpace($base)) {
        $infer = if ($pkgClass -and $pkgClass -ne 'unknown') { $pkgClass } else { $devClass }
        $label = Get-DeviceClassLabel -Class $infer
        if ($label) {
            $base = "未知设备（$label）"
        }
        else {
            $base = '未知设备'
        }
    }

    if ($Device.MergedCount -gt 1) {
        $base = ('{0} ×{1}' -f $base, [int]$Device.MergedCount)
    }
    elseif ($Device.PackageGroupCount -gt 1) {
        $base = ('Intel 芯片组设备 ×{0}' -f [int]$Device.PackageGroupCount)
    }

    return (Format-CIODIYDeviceDisplayName -Name $base -Device $Device -Package $Package)
}

function Get-DeviceDisplayName {
    param(
        $Device,
        $Package = $null
    )
    return (Resolve-CIODIYDeviceName -Device $Device -Package $Package)
}
