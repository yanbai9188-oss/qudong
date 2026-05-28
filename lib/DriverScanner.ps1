# Scan installed devices and driver status

function Get-DeviceHardwareIds {
    param([Parameter(Mandatory)][string]$InstanceId)
    $ids = New-Object System.Collections.ArrayList

    if    ($InstanceId -match '^(PCI\\VEN_[^\\]+(?:&[^\\]+)*)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(USB\\VID_[^\\]+(?:&[^\\]+)*)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(HDAUDIO\\[^\\]+(?:\\[^\\]+)*)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(ACPI\\[^\\]+)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(SWD\\[^\\]+(?:\\[^\\]+)*)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(ROOT\\[^\\]+(?:\\[^\\]+)*)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(HID\\[^\\]+(?:&[^\\]+)*)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(USBPRINT\\[^\\]+)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(BTH\\[^\\]+)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(SCSI\\[^\\]+)') { [void]$ids.Add($matches[1]) }

    if ($ids.Count -eq 0) {
        foreach ($key in @('DEVPKEY_Device_HardwareIds', 'DEVPKEY_Device_CompatibleIds')) {
            try {
                $prop = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $key -ErrorAction Stop
                foreach ($v in @($prop.Data)) {
                    if (-not [string]::IsNullOrWhiteSpace($v)) { [void]$ids.Add([string]$v) }
                }
            } catch { }
        }
    }

    if ($ids.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($InstanceId)) {
        [void]$ids.Add($InstanceId)
    }

    return @($ids | Select-Object -Unique)
}

function Get-DeviceDriverVersion {
    param([string]$InstanceId)
    try {
        $prop = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_Device_DriverVersion' -ErrorAction Stop
        return [string]$prop.Data
    } catch {
        return ''
    }
}

function Get-DeviceDriverProvider {
    param([string]$InstanceId)
    try {
        $prop = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_Device_DriverProvider' -ErrorAction Stop
        return [string]$prop.Data
    } catch {
        return ''
    }
}

function Get-EssentialDeviceClasses {
    return @('MEDIA', 'Net', 'Bluetooth', 'Display', 'System', 'HDC', 'USB', 'Ports', 'SCSIAdapter', 'Monitor')
}

function Get-OutdatedScanClasses {
    return @('MEDIA', 'Net', 'Bluetooth', 'Display', 'System', 'HDC', 'SCSIAdapter')
}

function Test-DriverRelevantDevice {
    param(
        [Parameter(Mandatory)]$Device,
        [string[]]$EssentialClasses
    )

    $id = [string]$Device.InstanceId
    $class = [string]$Device.Class
    $name = [string]$Device.FriendlyName

    if ($class -in @('Monitor', 'CDROM', 'DiskDrive', 'Volume', 'WPD', 'PrintQueue')) { return $false }
    if ($name -match 'Wi-Fi Direct Virtual|Virtual Adapter|VHD|DVD-ROM|DataTraveler|Generic Monitor|Integrated Monitor|USB Composite Device|USB Mass Storage') { return $false }

    if ($EssentialClasses -contains $class) { return $true }

    $patterns = @(
        '^PCI\\VEN_'
        '^USB\\VID_8087'
        '^HDAUDIO\\'
        '^ACPI\\INT'
        '^SWD\\DRIVERENUM\\'
        '^SCSI\\'
        '^ROOT\\NET\\'
        '^ROOT\\SYSTEM\\'
        '^ROOT\\MEDIA\\'
        '^ROOT\\DISPLAY\\'
        '^HID\\SYNA'
        '^HID\\ELAN'
        '^HID\\ALPS'
        '^USBPRINT\\'
        '^BTH\\'
    )
    foreach ($pattern in $patterns) {
        if ($id -match $pattern) { return $true }
    }

    if ($class -eq 'Unknown' -or [string]::IsNullOrWhiteSpace($class)) {
        if ($id -match '^(USBSTOR|CDROM|HID\\|USB\\ROOT_HUB|USB\\VID_0951|USB\\VID_0781|STORAGE\\Volume)') { return $false }
        if ($id -match '^(PCI\\|USB\\VID_|HDAUDIO\\|SWD\\DRIVERENUM\\)') { return $true }
    }

    return $false
}

function Invoke-DriverScan {
    param(
        [switch]$IncludeOkDevices,
        [switch]$AllDevices,
        [switch]$IncludeOutdated,
        [scriptblock]$OnProgress   # optional: { param($pct,$msg) }
    )

    $essential = Get-EssentialDeviceClasses
    $outdatedClasses = Get-OutdatedScanClasses
    $results = New-Object System.Collections.ArrayList

    # Stage 1: Enumerate PnP devices (~0.5s)
    # NOTE: Win32_PnPSignedDriver was removed — on Win11 24H2 that CIM query takes 20-60 s
    # because it enumerates every driver in the store.  We now batch-fetch
    # DEVPKEY_Device_DriverVersion / DriverProvider only for the small set of relevant
    # devices identified in Stage 3, which is 10-50x faster.
    if ($OnProgress) { try { & $OnProgress 20 '正在枚举设备...' } catch {} }
    $devices = @(Get-PnpDevice -ErrorAction SilentlyContinue)
    $targets = New-Object System.Collections.ArrayList

    if ($AllDevices) {
        foreach ($d in $devices) { [void]$targets.Add($d) }
    } else {
        foreach ($d in $devices) {
            if ($IncludeOutdated -and ($outdatedClasses -contains $d.Class) -and $d.Status -eq 'OK') {
                [void]$targets.Add($d); continue
            }
            if ($IncludeOkDevices -and ($essential -contains $d.Class)) {
                [void]$targets.Add($d); continue
            }
            if ($d.Status -eq 'OK' -and -not [string]::IsNullOrWhiteSpace($d.Class) -and $d.Class -ne 'Unknown') { continue }
            if (Test-DriverRelevantDevice -Device $d -EssentialClasses $essential) {
                [void]$targets.Add($d)
            }
        }
    }

    $sortedTargets = @($targets.ToArray() | Sort-Object Class, FriendlyName)

    # Stage 3: Pre-filter targets so we only do property fetch for items we'll actually keep
    $keptTargets = New-Object System.Collections.ArrayList
    foreach ($dev in $sortedTargets) {
        $isProblem = ($dev.Status -ne 'OK') -or (
            ([string]::IsNullOrWhiteSpace($dev.Class) -or $dev.Class -eq 'Unknown') -and
            (Test-DriverRelevantDevice -Device $dev -EssentialClasses $essential)
        )
        if (-not $AllDevices -and -not $IncludeOkDevices -and -not $IncludeOutdated -and -not $isProblem) { continue }
        if (-not $AllDevices -and $IncludeOkDevices -and -not $isProblem -and ($essential -notcontains $dev.Class)) { continue }
        if (-not $AllDevices -and $IncludeOutdated -and -not $isProblem -and ($outdatedClasses -notcontains $dev.Class)) { continue }
        [void]$keptTargets.Add(@{ Device = $dev; IsProblem = [bool]$isProblem })
    }

    # Stage 4: BATCH device property fetch — single Get-PnpDeviceProperty call per key.
    # All version/provider data also fetched here (replaces the old Win32_PnPSignedDriver query).
    if ($OnProgress) { try { & $OnProgress 55 '正在读取驱动属性...' } catch {} }
    $containerMap = @{}
    $hwIdMap = @{}
    $compatIdMap = @{}
    $driverVersionMap = @{}
    $driverProviderMap = @{}
    if ($keptTargets.Count -gt 0) {
        $allIds = @($keptTargets | ForEach-Object { $_.Device.InstanceId })
        try {
            $cprops = @(Get-PnpDeviceProperty -InstanceId $allIds -KeyName 'DEVPKEY_Device_ContainerId' -ErrorAction SilentlyContinue)
            foreach ($p in $cprops) {
                if ($p.InstanceId -and $p.Data) {
                    $containerMap[[string]$p.InstanceId] = [string]$p.Data
                }
            }
        } catch { }

        # Batch-fetch driver version and provider (replaces Win32_PnPSignedDriver)
        try {
            $vprops = @(Get-PnpDeviceProperty -InstanceId $allIds -KeyName 'DEVPKEY_Device_DriverVersion' -ErrorAction SilentlyContinue)
            foreach ($p in $vprops) {
                if ($p.InstanceId -and $p.Data) { $driverVersionMap[[string]$p.InstanceId] = [string]$p.Data }
            }
        } catch { }
        try {
            $pprops = @(Get-PnpDeviceProperty -InstanceId $allIds -KeyName 'DEVPKEY_Device_DriverProvider' -ErrorAction SilentlyContinue)
            foreach ($p in $pprops) {
                if ($p.InstanceId -and $p.Data) { $driverProviderMap[[string]$p.InstanceId] = [string]$p.Data }
            }
        } catch { }

        # Only fall back to property HWID lookup for InstanceIds whose regex parse below would fail.
        # The cheap regex covers PCI/USB/HDAUDIO/ACPI/etc, so we only batch-query for outliers.
        $needsHwidFetch = @($keptTargets | ForEach-Object { $_.Device.InstanceId } | Where-Object {
            $_ -notmatch '^(PCI\\|USB\\|HDAUDIO\\|ACPI\\|SWD\\|ROOT\\|HID\\|USBPRINT\\|BTH\\|SCSI\\)'
        })
        if ($needsHwidFetch.Count -gt 0) {
            try {
                $hprops = @(Get-PnpDeviceProperty -InstanceId $needsHwidFetch -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction SilentlyContinue)
                foreach ($p in $hprops) {
                    if ($p.InstanceId -and $p.Data) { $hwIdMap[[string]$p.InstanceId] = @($p.Data) }
                }
                $cprops2 = @(Get-PnpDeviceProperty -InstanceId $needsHwidFetch -KeyName 'DEVPKEY_Device_CompatibleIds' -ErrorAction SilentlyContinue)
                foreach ($p in $cprops2) {
                    if ($p.InstanceId -and $p.Data) { $compatIdMap[[string]$p.InstanceId] = @($p.Data) }
                }
            } catch { }
        }
    }

    # Stage 5: Build final result objects (no per-device WMI/PnP calls)
    if ($OnProgress) { try { & $OnProgress 80 '正在分析驱动状态...' } catch {} }
    foreach ($t in $keptTargets) {
        $dev = $t.Device
        $isProblem = $t.IsProblem
        $instId = [string]$dev.InstanceId

        $hwIds = @(Get-DeviceHardwareIdsFast -InstanceId $instId -PreFetchedHwids $hwIdMap[$instId] -PreFetchedCompat $compatIdMap[$instId])

        $name = if ($dev.FriendlyName) { $dev.FriendlyName } else { '(unnamed)' }
        $containerId = if ($containerMap.ContainsKey($instId)) { $containerMap[$instId] } else { '' }

        $ver  = if ($driverVersionMap.ContainsKey($instId))  { $driverVersionMap[$instId]  } else { '' }
        $prov = if ($driverProviderMap.ContainsKey($instId)) { $driverProviderMap[$instId] } else { '' }

        [void]$results.Add([PSCustomObject]@{
            FriendlyName   = $name
            Name           = $name
            Class          = $dev.Class
            Status         = $dev.Status
            InstanceId     = $instId
            HardwareIds    = @($hwIds | ForEach-Object { [string]$_ })
            DriverVersion  = $ver
            DriverProvider = $prov
            IsProblem      = [bool]$isProblem
            CategoryLabel  = Get-CategoryLabel -Class $dev.Class
            ContainerId    = $containerId
            DeviceClass    = (Get-CIODIYDeviceClass -Device @{ Class = $dev.Class; FriendlyName = $name; Name = $name; InstanceId = $instId; HardwareIds = $hwIds })
        })
    }

    return @($results.ToArray())
}

# Fast variant of Get-DeviceHardwareIds that uses pre-fetched property data when the
# instance id can't be parsed by the cheap regex. Avoids per-call Get-PnpDeviceProperty.
function Get-DeviceHardwareIdsFast {
    param(
        [Parameter(Mandatory)][string]$InstanceId,
        [string[]]$PreFetchedHwids,
        [string[]]$PreFetchedCompat
    )
    $ids = New-Object System.Collections.ArrayList

    if    ($InstanceId -match '^(PCI\\VEN_[^\\]+(?:&[^\\]+)*)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(USB\\VID_[^\\]+(?:&[^\\]+)*)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(HDAUDIO\\[^\\]+(?:\\[^\\]+)*)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(ACPI\\[^\\]+)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(SWD\\[^\\]+(?:\\[^\\]+)*)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(ROOT\\[^\\]+(?:\\[^\\]+)*)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(HID\\[^\\]+(?:&[^\\]+)*)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(USBPRINT\\[^\\]+)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(BTH\\[^\\]+)') { [void]$ids.Add($matches[1]) }
    elseif ($InstanceId -match '^(SCSI\\[^\\]+)') { [void]$ids.Add($matches[1]) }

    if ($ids.Count -eq 0) {
        if ($PreFetchedHwids) {
            foreach ($v in @($PreFetchedHwids)) {
                if (-not [string]::IsNullOrWhiteSpace($v)) { [void]$ids.Add([string]$v) }
            }
        }
        if ($PreFetchedCompat) {
            foreach ($v in @($PreFetchedCompat)) {
                if (-not [string]::IsNullOrWhiteSpace($v)) { [void]$ids.Add([string]$v) }
            }
        }
    }

    if ($ids.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($InstanceId)) {
        [void]$ids.Add($InstanceId)
    }

    return @($ids | Select-Object -Unique)
}

function Get-SystemInfoSummary {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        $osProfile = Get-SystemOsProfile
        $bb = Get-CimInstance Win32_BaseBoard
        return [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Manufacturer = $cs.Manufacturer
            Model        = $cs.Model
            BaseBoard    = "$($bb.Manufacturer) $($bb.Product)"
            OS           = if ($osProfile.Caption) { "$($osProfile.Caption) (Build $($osProfile.Build))" } else { $osProfile.Label }
            OsFamily     = $osProfile.Family
            OsLabel      = $osProfile.Label
            OsBuild      = $osProfile.Build
            OsArch       = $osProfile.Arch
        }
    } catch {
        return [PSCustomObject]@{ ComputerName = $env:COMPUTERNAME; OsFamily = 'unknown' }
    }
}
