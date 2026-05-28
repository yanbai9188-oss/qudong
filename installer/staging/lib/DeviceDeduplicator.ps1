# Merge duplicate physical devices / fix-plan rows (v1.6.4)

function Get-CIODIYDeviceKey {
    param($Device)

    $instanceId = [string]$Device.InstanceId
    $fname = if ($Device.FriendlyName) { [string]$Device.FriendlyName } else { [string]$Device.Name }

    if ($instanceId -match '^USBSTOR\\') {
        return 'usbstor:USB 存储设备'
    }

    if ($fname -match 'Mass Storage|大容量存储|USB 存储') {
        return 'usbstor:USB 存储设备'
    }

    if ($Device.ContainerId -and [string]$Device.ContainerId -notmatch '^(\{00000000|\s*$)') {
        return "container:$($Device.ContainerId)"
    }

    if ($instanceId -match '^(PCI\\VEN_[^\\&]+(?:&[^\\]+)*)') {
        return "pci:$($matches[1])"
    }
    if ($instanceId -match '^(USB\\VID_[^\\&]+(?:&[^\\]+)*)') {
        return "usb:$($matches[1])"
    }

    if ($Device.HardwareIds -and @($Device.HardwareIds).Count -gt 0) {
        return "hwid:$($Device.HardwareIds[0])"
    }

    return "name:$($Device.Class)|$fname"
}

function Get-DeviceDisplayPriority {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return 0 }
    if ($Name -match '^\s*\(unnamed\)\s*$|未知设备') { return 1 }
    if ($Name -match 'Virtual|Miniport|Direct Virtual|WAN Miniport|Microsoft Wi-Fi Direct') { return 2 }
    return 10 + [Math]::Min(20, $Name.Length)
}

function Get-DeviceStatusSeverity {
    param([string]$Status, [bool]$IsProblem)

    if ($IsProblem) { return 4 }
    switch ($Status) {
        'Error'    { return 4 }
        'Problem'  { return 4 }
        'Degraded' { return 3 }
        'Unknown'  { return 3 }
        'Warning'  { return 2 }
        default    { return 1 }
    }
}

function Merge-ScanDevices {
    param([Parameter(Mandatory)][array]$Devices)

    if ($Devices.Count -le 1) { return @($Devices) }

    $groups = @{}
    foreach ($d in $Devices) {
        $key = Get-CIODIYDeviceKey -Device $d
        if (-not $groups.ContainsKey($key)) { $groups[$key] = New-Object System.Collections.ArrayList }
        [void]$groups[$key].Add($d)
    }

    $merged = New-Object System.Collections.ArrayList
    foreach ($key in $groups.Keys) {
        $items = @($groups[$key])
        if ($items.Count -eq 1) {
            $one = $items[0]
            $one | Add-Member -NotePropertyName MergeKey -NotePropertyValue $key -Force
            $one | Add-Member -NotePropertyName DeviceClass -NotePropertyValue (Get-CIODIYDeviceClass -Device $one) -Force
            [void]$merged.Add($one)
            continue
        }

        $bestName = ($items | Sort-Object @{
            Expression = { Get-DeviceDisplayPriority -Name $_.FriendlyName }
            Descending = $true
        } | Select-Object -First 1).FriendlyName

        $worst = $items | Sort-Object @{
            Expression = { Get-DeviceStatusSeverity -Status $_.Status -IsProblem $_.IsProblem }
            Descending = $true
        } | Select-Object -First 1

        $allHw = New-Object System.Collections.Generic.HashSet[string]
        foreach ($it in $items) {
            foreach ($h in @($it.HardwareIds)) { if ($h) { [void]$allHw.Add([string]$h) } }
        }

        $rep = [PSCustomObject]@{
            FriendlyName   = $bestName
            Class          = $worst.Class
            Status         = $worst.Status
            InstanceId     = $worst.InstanceId
            HardwareIds    = @($allHw)
            DriverVersion  = $worst.DriverVersion
            DriverProvider = $worst.DriverProvider
            IsProblem      = [bool](@($items | Where-Object { $_.IsProblem }).Count -gt 0)
            CategoryLabel  = $worst.CategoryLabel
            ContainerId    = ($items | Where-Object { $_.ContainerId } | Select-Object -First 1).ContainerId
            MergeKey       = $key
            DeviceClass    = (Get-CIODIYDeviceClass -Device $worst)
            MergedCount    = $items.Count
        }
        [void]$merged.Add($rep)
    }

    return @($merged.ToArray())
}

function Find-DependencyDevice {
    param(
        [Parameter(Mandatory)]$DepPackage,
        [Parameter(Mandatory)][array]$ScanResults
    )

    $pkgClass = Get-CIODIYPackageClass -Package $DepPackage
    foreach ($d in $ScanResults) {
        if ((Get-CIODIYDeviceClass -Device $d) -eq $pkgClass) { return $d }
    }

    return [PSCustomObject]@{
        FriendlyName   = if ($DepPackage.Title) { $DepPackage.Title } else { $DepPackage.Id }
        Class          = 'System'
        Status         = 'Unknown'
        InstanceId     = "synthetic:$($DepPackage.Id)"
        HardwareIds    = @()
        DriverVersion  = ''
        DriverProvider = ''
        IsProblem      = $false
        CategoryLabel  = $pkgClass
        MergeKey       = "dep:$($DepPackage.Id)"
        DeviceClass    = $pkgClass
        IsSynthetic    = $true
    }
}

function Merge-FixPlanItems {
    param([Parameter(Mandatory)][array]$FixPlan)

    if ($FixPlan.Count -le 1) { return @($FixPlan) }

    $byKey = @{}
    foreach ($item in $FixPlan) {
        $devKey = if ($item.Device.MergeKey) { $item.Device.MergeKey } else { Get-CIODIYDeviceKey -Device $item.Device }
        $pkgId = if ($item.Package) { $item.Package.Id } else { 'none' }
        $rowKey = "$devKey|$pkgId"

        if (-not $byKey.ContainsKey($rowKey)) {
            $item | Add-Member -NotePropertyName MergeKey -NotePropertyValue $devKey -Force
            $byKey[$rowKey] = $item
            continue
        }

        $existing = $byKey[$rowKey]
        $existingScore = if ($null -ne $existing.Score) { [int]$existing.Score } else { 0 }
        $newScore = if ($null -ne $item.Score) { [int]$item.Score } else { 0 }
        if ($newScore -gt $existingScore) { $byKey[$rowKey] = $item }
    }

    $byDevice = @{}
    foreach ($item in $byKey.Values) {
        $devKey = $item.MergeKey
        if (-not $byDevice.ContainsKey($devKey)) {
            $byDevice[$devKey] = New-Object System.Collections.ArrayList
        }
        [void]$byDevice[$devKey].Add($item)
    }

    $result = New-Object System.Collections.ArrayList
    foreach ($devKey in $byDevice.Keys) {
        $items = @($byDevice[$devKey])
        $primary = @($items | Where-Object { -not $_.IsDependency })
        $deps = @($items | Where-Object { $_.IsDependency })

        if ($primary.Count -gt 0) {
            $best = @($primary | Sort-Object @{
                Expression = { if ($null -ne $_.Score) { [int]$_.Score } else { 0 } }
                Descending = $true
            })[0]
            [void]$result.Add($best)
        }
    }

    return @($result.ToArray())
}

function Attach-DependencyToParent {
    param([Parameter(Mandatory)][array]$FixPlan)

    if ($FixPlan.Count -eq 0) { return @() }

    $byPkgId = @{}
    foreach ($item in $FixPlan) {
        if ($item.Package -and $item.Package.Id) {
            $byPkgId[[string]$item.Package.Id] = $item
        }
    }

    $hiddenKeys = New-Object System.Collections.Generic.HashSet[string]
    foreach ($item in $FixPlan) {
        if (-not $item.Package -or -not $item.Package.Depends) { continue }
        $depList = New-Object System.Collections.ArrayList
        foreach ($depId in @($item.Package.Depends)) {
            if (-not $byPkgId.ContainsKey([string]$depId)) { continue }
            $depItem = $byPkgId[[string]$depId]
            if ($depItem -eq $item) { continue }
            [void]$depList.Add($depItem)
            $dk = if ($depItem.MergeKey) { $depItem.MergeKey } else { Get-CIODIYDeviceKey -Device $depItem.Device }
            [void]$hiddenKeys.Add("$dk|$depId")
            $depItem | Add-Member -NotePropertyName AttachedToParent -NotePropertyValue $true -Force
            $depItem | Add-Member -NotePropertyName HideFromList -NotePropertyValue $true -Force
        }
        if ($depList.Count -gt 0) {
            $item | Add-Member -NotePropertyName Dependencies -NotePropertyValue @($depList.ToArray()) -Force
        }
    }

    return @($FixPlan)
}

function Merge-UsbFixPlanRows {
    param([Parameter(Mandatory)][array]$FixPlan)

    $groups = @{}
    $order = New-Object System.Collections.ArrayList

    foreach ($item in $FixPlan) {
        $id = [string]$item.Device.InstanceId
        if ($id -match '^USBSTOR\\') {
            $key = 'usbplan:USB 存储设备'
        }
        elseif ([string]$item.Device.FriendlyName -match 'Mass Storage|大容量存储|USB 存储') {
            $key = 'usbplan:USB 存储设备'
        }
        else {
            $key = if ($item.MergeKey) { $item.MergeKey } else { Get-CIODIYDeviceKey -Device $item.Device }
        }

        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = New-Object System.Collections.ArrayList
            [void]$order.Add($key)
        }
        [void]$groups[$key].Add($item)
    }

    $merged = New-Object System.Collections.ArrayList
    foreach ($key in $order) {
        $items = @($groups[$key])
        if ($items.Count -eq 1) {
            [void]$merged.Add($items[0])
            continue
        }

        $best = @($items | Sort-Object @{
            Expression = { if ($null -ne $_.Score) { [int]$_.Score } else { 0 } }
            Descending = $true
        })[0]

        $subNames = New-Object System.Collections.ArrayList
        foreach ($it in $items) {
            $sub = if ($it.Device.InstanceId -match 'Disk|CdRom|Floppy') { '磁盘卷' }
                   elseif ($it.Device.InstanceId -match 'Partition') { '分区' }
                   else { '实例' }
            if ($subNames -notcontains $sub) { [void]$subNames.Add($sub) }
        }

        $best.Device | Add-Member -NotePropertyName MergedCount -NotePropertyValue $items.Count -Force
        $best | Add-Member -NotePropertyName UsbSubLabels -NotePropertyValue @($subNames.ToArray()) -Force
        $best | Add-Member -NotePropertyName MergeKey -NotePropertyValue $key -Force
        [void]$merged.Add($best)
    }

    return @($merged.ToArray())
}

function Finalize-FixPlanDisplay {
    param([Parameter(Mandatory)][array]$FixPlan)

    $plan = Attach-DependencyToParent -FixPlan @($FixPlan)

    $hidden = @($plan | Where-Object { $_.HideFromList })
    $visible = @($plan | Where-Object { -not $_.HideFromList })

    $visible = Merge-FixPlanItems -FixPlan $visible
    $visible = Merge-UsbFixPlanRows -FixPlan $visible
    $visible = Merge-PackageDuplicateRows -FixPlan $visible

    return @($visible) + @($hidden)
}
