# Post-install driver verification

function Wait-DeviceSettle {
    param([int]$Seconds = 10)
    Start-Sleep -Seconds $Seconds
}

function Get-VerifyTypeForDevice {
    param($Device, $Package)

    if ($Package -and $Package.Verify) { return [string]$Package.Verify }

    $cat = if ($Package -and $Package.Category) { $Package.Category.ToLower() } else { '' }
    $cls = if ($Device.Class) { $Device.Class } else { '' }

    switch ($cat) {
        'wifi' { return 'wifi' }
        'lan' { return 'net' }
        'bluetooth' { return 'bluetooth' }
        'audio' { return 'audio' }
        'gpu' { return 'gpu' }
        'storage' { return 'storage' }
    }

    switch ($cls) {
        'Net' { return 'net' }
        'Bluetooth' { return 'bluetooth' }
        'MEDIA' { return 'audio' }
        'Display' { return 'gpu' }
        'HDC' { return 'storage' }
        'SCSIAdapter' { return 'storage' }
    }

    return 'enum'
}

function Test-NetDriverVerify {
    param([string]$InstanceId, [string]$FriendlyName)

    $checks = New-Object System.Collections.ArrayList
    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue)
    $match = $adapters | Where-Object {
        $_.Status -eq 'Up' -or $_.Status -eq 'Disconnected'
    } | Select-Object -First 1

    [void]$checks.Add([PSCustomObject]@{ name = 'adapter_present'; passed = ($null -ne $match) })
    if ($match) {
        [void]$checks.Add([PSCustomObject]@{ name = 'adapter_status'; passed = ($match.Status -in @('Up', 'Disconnected')) })
    }

    $passed = @($checks | Where-Object { -not $_.passed }).Count -eq 0
    return [PSCustomObject]@{ verified = $passed; checks = @($checks); verifyType = 'net' }
}

function Test-WifiDriverVerify {
    param([string]$InstanceId)

    $checks = New-Object System.Collections.ArrayList
    $wifi = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match 'Wi-Fi|Wireless|WLAN|802\.11' })
    [void]$checks.Add([PSCustomObject]@{ name = 'wifi_adapter'; passed = ($wifi.Count -gt 0) })
    if ($wifi.Count -gt 0) {
        [void]$checks.Add([PSCustomObject]@{ name = 'wifi_up'; passed = ($wifi[0].Status -in @('Up', 'Disconnected')) })
    }
    $passed = @($checks | Where-Object { -not $_.passed }).Count -eq 0
    return [PSCustomObject]@{ verified = $passed; checks = @($checks); verifyType = 'wifi' }
}

function Test-AudioDriverVerify {
    param([string]$InstanceId)

    $checks = New-Object System.Collections.ArrayList
    $audioDev = @(Get-PnpDevice -Class MEDIA -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })
    [void]$checks.Add([PSCustomObject]@{ name = 'media_device_ok'; passed = ($audioDev.Count -gt 0) })

    try {
        $endpoints = @(Get-CimInstance -ClassName Win32_SoundDevice -ErrorAction SilentlyContinue)
        [void]$checks.Add([PSCustomObject]@{ name = 'sound_endpoint'; passed = ($endpoints.Count -gt 0) })
    } catch {
        [void]$checks.Add([PSCustomObject]@{ name = 'sound_endpoint'; passed = $false })
    }

    $passed = @($checks | Where-Object { -not $_.passed }).Count -eq 0
    return [PSCustomObject]@{ verified = $passed; checks = @($checks); verifyType = 'audio' }
}

function Test-BluetoothDriverVerify {
    param([string]$InstanceId)

    $checks = New-Object System.Collections.ArrayList
    $bt = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })
    [void]$checks.Add([PSCustomObject]@{ name = 'bluetooth_enum'; passed = ($bt.Count -gt 0) })

    try {
        $radio = Get-CimInstance -Namespace root/WMI -ClassName MSN_DeviceProxy -ErrorAction SilentlyContinue
        [void]$checks.Add([PSCustomObject]@{ name = 'bluetooth_radio'; passed = ($null -ne $radio) })
    } catch {
        [void]$checks.Add([PSCustomObject]@{ name = 'bluetooth_radio'; passed = ($bt.Count -gt 0) })
    }

    $passed = @($checks | Where-Object { -not $_.passed }).Count -eq 0
    return [PSCustomObject]@{ verified = $passed; checks = @($checks); verifyType = 'bluetooth' }
}

function Test-GpuDriverVerify {
    param([string]$InstanceId)

    $checks = New-Object System.Collections.ArrayList
    $gpu = @(Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })
    [void]$checks.Add([PSCustomObject]@{ name = 'display_ok'; passed = ($gpu.Count -gt 0) })

    try {
        $v = Get-DeviceDriverVersion -InstanceId $gpu[0].InstanceId
        [void]$checks.Add([PSCustomObject]@{ name = 'driver_version'; passed = (-not [string]::IsNullOrWhiteSpace($v)) })
    } catch {
        [void]$checks.Add([PSCustomObject]@{ name = 'driver_version'; passed = $false })
    }

    $passed = @($checks | Where-Object { -not $_.passed }).Count -eq 0
    return [PSCustomObject]@{ verified = $passed; checks = @($checks); verifyType = 'gpu' }
}

function Test-StorageDriverVerify {
    param([string]$InstanceId)

    $checks = New-Object System.Collections.ArrayList
    $stor = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
        $_.Class -in @('HDC', 'SCSIAdapter', 'DiskDrive') -and $_.Status -eq 'OK'
    })
    [void]$checks.Add([PSCustomObject]@{ name = 'storage_enum'; passed = ($stor.Count -gt 0) })
    $passed = @($checks | Where-Object { -not $_.passed }).Count -eq 0
    return [PSCustomObject]@{ verified = $passed; checks = @($checks); verifyType = 'storage' }
}

function Test-EnumDriverVerify {
    param(
        [Parameter(Mandatory)][string]$InstanceId,
        [int]$WaitSeconds = 10
    )

    Wait-DeviceSettle -Seconds $WaitSeconds
    $checks = New-Object System.Collections.ArrayList

    try {
        $dev = Get-PnpDevice -InstanceId $InstanceId -ErrorAction Stop
        [void]$checks.Add([PSCustomObject]@{ name = 'device_present'; passed = ($null -ne $dev) })
        [void]$checks.Add([PSCustomObject]@{ name = 'device_status_ok'; passed = ($dev.Status -eq 'OK') })
    } catch {
        [void]$checks.Add([PSCustomObject]@{ name = 'device_present'; passed = $false })
    }

    $passed = @($checks | Where-Object { -not $_.passed }).Count -eq 0
    return [PSCustomObject]@{ verified = $passed; checks = @($checks); verifyType = 'enum' }
}

function Test-DriverInstall {
    param(
        [Parameter(Mandatory)]$Device,
        $Package,
        [int]$WaitSeconds = 10,
        [scriptblock]$OnLog
    )

    $verifyType = Get-VerifyTypeForDevice -Device $Device -Package $Package
    Write-AppLog "Verify ($verifyType): $($Device.FriendlyName)" -OnLog $OnLog
    Wait-DeviceSettle -Seconds $WaitSeconds

    switch ($verifyType) {
        'wifi' { $result = Test-WifiDriverVerify -InstanceId $Device.InstanceId }
        'net' { $result = Test-NetDriverVerify -InstanceId $Device.InstanceId -FriendlyName $Device.FriendlyName }
        'audio' { $result = Test-AudioDriverVerify -InstanceId $Device.InstanceId }
        'bluetooth' { $result = Test-BluetoothDriverVerify -InstanceId $Device.InstanceId }
        'gpu' { $result = Test-GpuDriverVerify -InstanceId $Device.InstanceId }
        'storage' { $result = Test-StorageDriverVerify -InstanceId $Device.InstanceId }
        default { $result = Test-EnumDriverVerify -InstanceId $Device.InstanceId -WaitSeconds 0 }
    }

    foreach ($c in @($result.checks)) {
        $flag = if ($c.passed) { 'OK' } else { 'FAIL' }
        Write-AppLog ("  check {0}: {1}" -f $c.name, $flag) -OnLog $OnLog
    }

    return [PSCustomObject]@{
        verified   = [bool]$result.verified
        verifyType = $result.verifyType
        checks     = @($result.checks)
    }
}
