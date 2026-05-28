# Hardware profile — machine identity for smarter driver scoring (v1.3.2)

$script:CachedHardwareProfile = $null

function Normalize-OemBrand {
    param([string]$Raw)

    if ([string]::IsNullOrWhiteSpace($Raw)) { return '' }
    $t = $Raw.Trim()
    if ($t -match '^(Default string|To be filled|System Product|Not Specified|None)$') { return '' }

    $map = @{
        'LENOVO'            = 'Lenovo'
        'ASUSTEK'           = 'ASUS'
        'ASUS'              = 'ASUS'
        'DELL'              = 'Dell'
        'HEWLETT-PACKARD'   = 'HP'
        'HP'                = 'HP'
        'MICRO-STAR'        = 'MSI'
        'MSI'               = 'MSI'
        'GIGABYTE'          = 'Gigabyte'
        'ACER'              = 'Acer'
        'HUAWEI'            = 'Huawei'
        'HONOR'             = 'Honor'
        'XIAOMI'            = 'Xiaomi'
        'APPLE'             = 'Apple'
        'SAMSUNG'           = 'Samsung'
        'THINKPAD'          = 'Lenovo'
        'HASEE'             = 'Hasee'
        'MECHREVO'          = 'Mechrevo'
        'COLORFUL'          = 'Colorful'
        'MAXSUN'            = 'Maxsun'
        'INTEL'             = 'Intel'
        'AMD'               = 'AMD'
        'NVIDIA'            = 'NVIDIA'
        'REALTEK'           = 'Realtek'
    }

    $upper = $t.ToUpperInvariant()
    foreach ($k in $map.Keys) {
        if ($upper -like "*$k*") { return $map[$k] }
    }
    return $t
}

function Get-WindowsReleaseLabel {
    param(
        [int]$Build,
        [string]$Family
    )

    if ($Family -eq 'win11') {
        if ($Build -ge 26100) { return 'Win11 24H2' }
        if ($Build -ge 22631) { return 'Win11 23H2' }
        if ($Build -ge 22000) { return 'Win11 21H2+' }
        return 'Win11'
    }
    if ($Family -eq 'win10') {
        if ($Build -ge 19045) { return 'Win10 22H2' }
        if ($Build -ge 19044) { return 'Win10 21H2' }
        if ($Build -ge 19043) { return 'Win10 21H1' }
        if ($Build -ge 19042) { return 'Win10 20H2' }
        if ($Build -ge 19041) { return 'Win10 2004' }
        if ($Build -ge 18363) { return 'Win10 1909' }
        if ($Build -ge 10240) { return 'Win10' }
    }
    return ''
}

function Format-CpuLabel {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return '未知' }
    $n = $Name -replace '\s+', ' '
    $n = $n -replace '\(R\)|\(TM\)|CPU @|Processor', ''
    $n = $n.Trim(' @')
    if ($n.Length -gt 48) { $n = $n.Substring(0, 45) + '...' }
    return $n
}

function Format-GpuLabel {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return '未知' }
    if ($Name -match 'Microsoft Basic|Remote Desktop|Virtual') { return '' }
    $n = $Name -replace '\s+', ' '
    if ($n -match 'GeForce\s+(RTX\s*\d+\S*)') { return ($matches[1] -replace '\s', '') }
    if ($n -match 'GeForce\s+(GTX\s*\d+\S*)') { return ($matches[1] -replace '\s', '') }
    if ($n -match 'GeForce\s+(.+)') { return $matches[1].Trim() }
    if ($n -match 'Intel.*?(UHD Graphics \d+|Iris Xe|Iris Plus|HD Graphics \d+)') { return "Intel $($matches[1])" }
    if ($n -match 'AMD Radeon\s+(.+)') { return "Radeon $($matches[1].Trim())" }
    if ($n.Length -gt 40) { $n = $n.Substring(0, 37) + '...' }
    return $n
}

function Get-PrimaryNetworkLabel {
    try {
        $devices = @(Get-PnpDevice -Class Net -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -eq 'OK' -and
            [string]$_.FriendlyName -notmatch 'Virtual|Loopback|WAN Miniport|Bluetooth|TAP-|Hyper-V|VMware|Npcap|Kernel Debug|Wi-Fi Direct|Debug Network'
        })
        if ($devices.Count -eq 0) { return '' }

        $wifi = @($devices | Where-Object { [string]$_.FriendlyName -match 'Wi-Fi|Wireless|WLAN|AX\d|AC \d|802\.11' })
        if ($wifi.Count -gt 0) {
            return (Format-DeviceShortName -Name $wifi[0].FriendlyName -Kind 'network')
        }
        return (Format-DeviceShortName -Name $devices[0].FriendlyName -Kind 'network')
    } catch {
        return ''
    }
}

function Get-PrimaryAudioLabel {
    try {
        $devices = @(Get-PnpDevice -Class MEDIA -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -eq 'OK' -and
            [string]$_.FriendlyName -notmatch 'NVIDIA Virtual|AMD High Definition Audio Device$|Microsoft|Streaming'
        })
        if ($devices.Count -eq 0) { return '' }

        $preferred = @($devices | Where-Object {
            [string]$_.FriendlyName -match 'Realtek|Intel Smart Sound|Conexant|Synaptics|High Definition Audio'
        })
        $pick = if ($preferred.Count -gt 0) { $preferred[0] } else { $devices[0] }
        return (Format-DeviceShortName -Name $pick.FriendlyName -Kind 'audio')
    } catch {
        return ''
    }
}

function Format-DeviceShortName {
    param(
        [string]$Name,
        [string]$Kind = 'device'
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    if ($Name -match 'Intel\(R\)\s+(.+?)\s+(Wi-Fi|Wireless|Dual Band|AX\d|AC \d)') {
        return "Intel $($matches[2].Trim())"
    }
    if ($Name -match 'Realtek\s+(.+)') {
        $part = $matches[1].Trim()
        if ($part -match 'ALC\d+') { return $matches[0] }
        if ($Kind -eq 'audio') { return "Realtek $part" }
        return "Realtek $part"
    }
    if ($Name -match 'ALC\d+') { return $matches[0] }
    if ($Name.Length -gt 36) { return $Name.Substring(0, 33) + '...' }
    return $Name
}

function Get-CpuPlatform {
    param([string]$CpuName, [string]$CpuManufacturer)

    $blob = ("$CpuManufacturer $CpuName").ToLowerInvariant()
    if ($blob -match 'amd|authenticamd|ryzen|threadripper|epyc') { return 'AMD' }
    if ($blob -match 'intel|genuineintel|xeon|core i[3579]|celeron|pentium') { return 'Intel' }
    return '未知'
}

function Resolve-MachineIdentity {
    param(
        [string]$Manufacturer,
        [string]$Model,
        [string]$BaseBoardManufacturer,
        [string]$BaseBoardProduct
    )

    $brand = Normalize-OemBrand $Manufacturer
    $model = $Model.Trim()
    $generic = @('Default string', 'System Product Name', 'To be filled by O.E.M.', 'Not Specified', 'None', '')

    if ($generic -contains $model -or $model -match '^Default') {
        if (-not [string]::IsNullOrWhiteSpace($BaseBoardProduct) -and ($generic -notcontains $BaseBoardProduct.Trim())) {
            $model = $BaseBoardProduct.Trim()
            if (-not $brand -or $brand -eq '未知品牌') {
                $bbBrandNorm = Normalize-OemBrand $BaseBoardManufacturer
                if ($bbBrandNorm) { $brand = $bbBrandNorm }
            }
        }
    }

    $bbBrand = Normalize-OemBrand $BaseBoardManufacturer
    if ((-not $brand -or $brand -eq '未知品牌') -and $bbBrand) { $brand = $bbBrand }
    if (-not $brand) { $brand = '未知品牌' }
    if (-not $model -or $generic -contains $model) { $model = '未知型号' }

    $title = if ($model -eq '未知型号') {
        if ($brand -ne '未知品牌') { $brand } else { '自定义/准系统' }
    } else {
        if ($brand -ne '未知品牌') { "$brand $model" } else { $model }
    }
    return [PSCustomObject]@{
        Brand = $brand
        Model = $model
        Title = $title
    }
}

function Get-HardwareProfile {
    param([switch]$Refresh)

    if (-not $Refresh -and $script:CachedHardwareProfile) {
        return $script:CachedHardwareProfile
    }

    $os = Get-SystemOsProfile
    $release = Get-WindowsReleaseLabel -Build $os.Build -Family $os.Family

    $manufacturer = ''
    $model = ''
    $bbMfg = ''
    $bbProd = ''
    $cpuName = ''
    $cpuMfg = ''
    $gpuName = ''
    $biosVendor = ''
    $biosVersion = ''

    # Use ManagementObjectSearcher (raw .NET WMI) which is faster than Get-CimInstance
    # because it skips PowerShell's CIM object wrapping. Combined with parallel
    # execution via Runspace, this cuts hardware enumeration roughly in half.
    $cimResults = @{}
    $useParallel = $true
    try {
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $pool = [RunspaceFactory]::CreateRunspacePool(1, 5, $iss, $Host)
        $pool.Open()

        $queries = @(
            @{ Name = 'CS';    Class = 'Win32_ComputerSystem';   Props = 'Manufacturer,Model' }
            @{ Name = 'BB';    Class = 'Win32_BaseBoard';        Props = 'Manufacturer,Product' }
            @{ Name = 'CPU';   Class = 'Win32_Processor';        Props = 'Name,Manufacturer' }
            @{ Name = 'Video'; Class = 'Win32_VideoController';  Props = 'Name' }
            @{ Name = 'BIOS';  Class = 'Win32_BIOS';             Props = 'Manufacturer,SMBIOSBIOSVersion,Version' }
        )

        $jobs = @()
        foreach ($q in $queries) {
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript({
                param($className, $props)
                try {
                    $query = "SELECT $props FROM $className"
                    $searcher = New-Object System.Management.ManagementObjectSearcher $query
                    $items = @()
                    foreach ($mo in $searcher.Get()) {
                        $h = @{}
                        foreach ($p in ($props -split ',')) {
                            try { $h[$p] = [string]$mo.GetPropertyValue($p) } catch { $h[$p] = '' }
                        }
                        $items += [PSCustomObject]$h
                        if ($items.Count -ge 8) { break }
                    }
                    $searcher.Dispose()
                    return $items
                } catch { return @() }
            })
            [void]$ps.AddArgument($q.Class)
            [void]$ps.AddArgument($q.Props)
            $jobs += @{ Name = $q.Name; PS = $ps; Async = $ps.BeginInvoke() }
        }

        foreach ($j in $jobs) {
            try {
                $r = $j.PS.EndInvoke($j.Async)
                $cimResults[$j.Name] = @($r)
            } catch { $cimResults[$j.Name] = @() }
            $j.PS.Dispose()
        }
        $pool.Close(); $pool.Dispose()
    } catch {
        $useParallel = $false
    }

    if (-not $useParallel) {
        try { $cimResults['CS']    = @(Get-CimInstance Win32_ComputerSystem -EA Stop) } catch {}
        try { $cimResults['BB']    = @(Get-CimInstance Win32_BaseBoard -EA Stop) } catch {}
        try { $cimResults['CPU']   = @(Get-CimInstance Win32_Processor -EA Stop) } catch {}
        try { $cimResults['Video'] = @(Get-CimInstance Win32_VideoController -EA Stop) } catch {}
        try { $cimResults['BIOS']  = @(Get-CimInstance Win32_BIOS -EA Stop) } catch {}
    }

    $cs = $cimResults['CS'] | Select-Object -First 1
    if ($cs) {
        $manufacturer = [string]$cs.Manufacturer
        $model = [string]$cs.Model
    }

    $bb = $cimResults['BB'] | Select-Object -First 1
    if ($bb) {
        $bbMfg = [string]$bb.Manufacturer
        $bbProd = [string]$bb.Product
    }

    $cpu = $cimResults['CPU'] | Select-Object -First 1
    if ($cpu) {
        $cpuName = [string]$cpu.Name
        $cpuMfg = [string]$cpu.Manufacturer
    }

    $gpus = @($cimResults['Video'] | Where-Object {
        [string]$_.Name -notmatch 'Microsoft Basic|Remote Desktop|Virtual Display'
    })
    if ($gpus.Count -gt 0) { $gpuName = [string]$gpus[0].Name }

    $bios = $cimResults['BIOS'] | Select-Object -First 1
    if ($bios) {
        $biosVendor = [string]$bios.Manufacturer
        $biosVersion = [string]$bios.SMBIOSBIOSVersion
        if (-not $biosVersion) { $biosVersion = [string]$bios.Version }
    }

    $identity = Resolve-MachineIdentity -Manufacturer $manufacturer -Model $model `
        -BaseBoardManufacturer $bbMfg -BaseBoardProduct $bbProd

    $platform = Get-CpuPlatform -CpuName $cpuName -CpuManufacturer $cpuMfg
    $cpuLabel = Format-CpuLabel -Name $cpuName
    $gpuLabel = Format-GpuLabel -Name $gpuName
    if (-not $gpuLabel) { $gpuLabel = '核显/未知' }

    if ($identity.Title -match '未知|自定义|准系统' -and $cpuLabel -ne '未知') {
        $identity = [PSCustomObject]@{
            Brand = if ($identity.Brand -ne '未知品牌') { $identity.Brand } else { "${platform}平台" }
            Model = $cpuLabel
            Title = "${platform}平台 · $cpuLabel"
        }
    }

    $network = Get-PrimaryNetworkLabel
    $audio = Get-PrimaryAudioLabel

    $systemShort = if ($release) { $release } else { $os.Label }
    $platformLine = "$systemShort | ${platform}平台"
    if ($os.Arch) { $platformLine += " | $($os.Arch)" }

    $biosLabel = if ($biosVendor -and $biosVersion) { "$biosVendor $biosVersion".Trim() } else { '' }

    $vendors = New-Object System.Collections.Generic.HashSet[string]
    foreach ($v in @($identity.Brand, $platform, 'Intel', 'Realtek', 'AMD', 'NVIDIA')) {
        if ($v -and $v -ne '未知品牌' -and $v -ne '未知') {
            [void]$vendors.Add($v.ToLowerInvariant())
        }
    }
    if ($network -match 'Intel') { [void]$vendors.Add('intel') }
    if ($network -match 'Realtek') { [void]$vendors.Add('realtek') }
    if ($audio -match 'Realtek') { [void]$vendors.Add('realtek') }
    if ($gpuLabel -match 'RTX|GeForce|NVIDIA') { [void]$vendors.Add('nvidia') }

    $script:CachedHardwareProfile = [PSCustomObject]@{
        Manufacturer   = $identity.Brand
        Model          = $identity.Model
        MachineTitle   = $identity.Title
        Brand          = $identity.Brand
        BrandKey       = $identity.Brand.ToLowerInvariant()
        CPU            = $cpuLabel
        GPU            = $gpuLabel
        Network        = if ($network) { $network } else { '未知' }
        Audio          = if ($audio) { $audio } else { '未知' }
        BIOS           = if ($biosLabel) { $biosLabel } else { '未知' }
        System         = $systemShort
        Platform       = $platform
        PlatformLine   = $platformLine
        SystemFull     = if ($os.Caption) { "$($os.Caption) (Build $($os.Build))" } else { $os.Label }
        BaseBoard      = "$bbMfg $bbProd".Trim()
        Vendors        = @($vendors)
        OsFamily       = $os.Family
        OsBuild        = $os.Build
        SpecLine       = "CPU: $cpuLabel  |  GPU: $gpuLabel"
        ExtraLine      = "网卡: $(if ($network) { $network } else { '未知' })  |  音频: $(if ($audio) { $audio } else { '未知' })"
    }

    return $script:CachedHardwareProfile
}

function Clear-HardwareProfileCache {
    $script:CachedHardwareProfile = $null
}
