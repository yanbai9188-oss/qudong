# Scenario-based filtering — DeviceClass first (v1.6.6)

function Get-EffectiveDeviceClass {
    param($Device)

    if ($Device.DeviceClass) { return [string]$Device.DeviceClass }
    $cls = Get-CIODIYDeviceClass -Device $Device
    if ($cls -ne 'unknown') { return $cls }

    $id = [string]$Device.InstanceId
    $name = [string]$Device.FriendlyName
    if ($id -match '^USBSTOR\\' -or $name -match 'Mass Storage|大容量存储|USB 存储') {
        return 'usb_storage'
    }
    return $cls
}

function Test-ScenarioDeviceClass {
    param(
        [Parameter(Mandatory)]$Device,
        [string]$Scenario = 'all'
    )

    if ([string]::IsNullOrWhiteSpace($Scenario) -or $Scenario -eq 'all') { return $true }

    $cls = Get-EffectiveDeviceClass -Device $Device
    switch ($Scenario) {
        'network' {
            return ($cls -in @('network_wifi', 'network_lan', 'bluetooth'))
        }
        'usb' {
            return ($cls -in @('usb', 'usb_storage'))
        }
        'audio' {
            return ($cls -in @('audio'))
        }
        default { return $true }
    }
}

function Get-ScenarioCatalog {
    return @{
        all = @{
            Id          = 'all'
            Label       = '全部'
            Description = 'Scan all driver issues'
        }
        audio = @{
            Id          = 'audio'
            Label       = '无声音 / 音频'
            Description = 'Audio devices and drivers'
            DeviceClasses = @('audio')
        }
        network = @{
            Id          = 'network'
            Label       = '无网络 / Wi-Fi'
            Description = 'WiFi, LAN, Bluetooth'
            DeviceClasses = @('network_wifi', 'network_lan', 'bluetooth')
        }
        usb = @{
            Id          = 'usb'
            Label       = 'USB 无法识别'
            Description = 'USB storage and host controllers'
            DeviceClasses = @('usb', 'usb_storage')
        }
    }
}

function Get-ScenarioInfo {
    param([string]$Scenario = 'all')
    $cat = Get-ScenarioCatalog
    if ($cat.ContainsKey($Scenario)) { return $cat[$Scenario] }
    return $cat['all']
}

function Test-DeviceMatchesScenario {
    param(
        [Parameter(Mandatory)]$Device,
        [string]$Scenario = 'all'
    )
    return (Test-ScenarioDeviceClass -Device $Device -Scenario $Scenario)
}

function Test-FixPlanItemMatchesScenario {
    param(
        [Parameter(Mandatory)]$Item,
        [string]$Scenario = 'all'
    )

    if ([string]::IsNullOrWhiteSpace($Scenario) -or $Scenario -eq 'all') { return $true }
    if ($Item.HideFromList) { return $false }
    return (Test-ScenarioDeviceClass -Device $Item.Device -Scenario $Scenario)
}

function Sort-FixPlanByScenario {
    param(
        [Parameter(Mandatory)][array]$FixPlan,
        [string]$Scenario = 'all'
    )

    if ($Scenario -eq 'network') {
        return @($FixPlan | Sort-Object @{
            Expression = {
                $cls = Get-EffectiveDeviceClass -Device $_.Device
                switch ($cls) {
                    'network_lan' { 0 }
                    'network_wifi' { 1 }
                    'bluetooth' { 2 }
                    default { 3 }
                }
            }
        })
    }
    if ($Scenario -eq 'usb') {
        return @($FixPlan | Sort-Object @{
            Expression = {
                $cls = Get-EffectiveDeviceClass -Device $_.Device
                if ($cls -eq 'usb_storage') { 0 } else { 1 }
            }
        })
    }
    return @($FixPlan)
}

function Filter-FixPlanByScenario {
    param(
        [Parameter(Mandatory)][array]$FixPlan,
        [string]$Scenario = 'all'
    )
    if ([string]::IsNullOrWhiteSpace($Scenario) -or $Scenario -eq 'all') { return @($FixPlan) }
    $filtered = @($FixPlan | Where-Object { Test-FixPlanItemMatchesScenario -Item $_ -Scenario $Scenario })
    return @(Sort-FixPlanByScenario -FixPlan $filtered -Scenario $Scenario)
}

function Filter-ScanResultsByScenario {
    param(
        [Parameter(Mandatory)][array]$ScanResults,
        [string]$Scenario = 'all'
    )
    if ([string]::IsNullOrWhiteSpace($Scenario) -or $Scenario -eq 'all') { return @($ScanResults) }
    return @($ScanResults | Where-Object { Test-DeviceMatchesScenario -Device $_ -Scenario $Scenario })
}
