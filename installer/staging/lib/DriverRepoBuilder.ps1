# CIODIY Driver Repository Builder (v1.6.0)

function Get-DriverFolderToPackageMap {
    return @{
        'intel_wifi'                      = 'intel_wifi'
        'intel_chipset'                   = 'intel_chipset'
        'intel_bluetooth'                 = 'intel_bluetooth'
        'intel_mei'                       = 'intel_mei'
        'intel_sst'                       = 'intel_sst'
        'intel_dtt'                       = 'intel_dtt'
        'intel_platform'                  = 'intel_platform'
        'intel_serialio'                  = 'intel_serialio'
        'intel_rst'                       = 'intel_rst'
        'realtek_lan'                     = 'realtek_lan'
        'realtek_audio'                   = 'realtek_audio'
        'amd_chipset'                     = 'amd_chipset'
        'Intel_7260_WiFi_16.10.0.5'       = 'intel_wifi_7260'
        'Intel_7260_Bluetooth_20.100.5.1' = 'intel_bluetooth_7260'
        'Realtek_LAN_8168'                = 'realtek_lan_8168'
        'intel_graphics'                  = 'intel_graphics'
        'intel_usb3'                      = 'intel_usb3'
        'intel_lan_i219'                  = 'intel_lan_i219'
        'intel_wifi_8260'                 = 'intel_wifi_8260'
        'realtek_cardreader'              = 'realtek_cardreader'
        'Intel_DisplayAudio'              = 'intel_display_audio'
        'nvidia_dch_gpu'                  = 'nvidia_dch_gpu'
        'synaptics_touchpad'              = 'synaptics_touchpad'
        'elan_touchpad'                   = 'elan_touchpad'
        'hp_printer_pcl'                  = 'hp_printer_pcl'
        'canon_printer_ufrii'             = 'canon_printer_ufrii'
    }
}

function Resolve-DriverPackageId {
    param([string]$FolderName)

    $map = Get-DriverFolderToPackageMap
    if ($map.ContainsKey($FolderName)) { return $map[$FolderName] }

    $n = ($FolderName -replace '[^a-zA-Z0-9]+', '_').Trim('_').ToLowerInvariant()
    if ($n) { return $n }
    return $FolderName
}

function Get-InfFileMetadata {
    param([Parameter(Mandatory)][string]$InfPath)

    $hwids = @(Get-InfHardwareIds -InfPath $InfPath)
    $provider = ''
    $version = ''
    $manufacturer = ''

    foreach ($line in (Get-Content -Path $InfPath -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*[;#]') { continue }
        if (-not $provider -and $line -match 'Provider\s*=\s*"?([^";]+)"?') { $provider = $matches[1].Trim() }
        if (-not $manufacturer -and $line -match 'Manufacturer\s*=\s*"?([^";]+)"?') { $manufacturer = $matches[1].Trim() }
        if (-not $version -and $line -match 'DriverVer\s*=\s*[\d,\.]+\,([\d\.]+)') { $version = $matches[1].Trim() }
        if (-not $version -and $line -match 'DriverVer\s*=\s*([\d\.]+)') { $version = $matches[1].Trim() }
    }

    return [PSCustomObject]@{
        Path         = $InfPath
        Hwids        = $hwids
        Provider     = $provider
        Manufacturer = $manufacturer
        Version      = $version
    }
}

function Test-DriverFolderReady {
    param([Parameter(Mandatory)][string]$FolderPath)

    $issues = New-Object System.Collections.ArrayList
    if (-not (Test-Path $FolderPath)) {
        return [PSCustomObject]@{ Ok = $false; InfCount = 0; Issues = @('文件夹不存在') }
    }

    $infs = @(Get-ChildItem -Path $FolderPath -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue)
    if ($infs.Count -eq 0) {
        [void]$issues.Add('缺少 INF 文件')
        return [PSCustomObject]@{ Ok = $false; InfCount = 0; Issues = @($issues.ToArray()) }
    }

    Get-ChildItem -Path $FolderPath -Filter 'catalog_driver.cab' -Recurse -EA SilentlyContinue | Remove-Item -Force -EA SilentlyContinue

    $hwidSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($inf in $infs) {
        try {
            $meta = Get-InfFileMetadata -InfPath $inf.FullName
            foreach ($h in @($meta.Hwids)) { [void]$hwidSet.Add($h) }
            if ($meta.Hwids.Count -eq 0) { [void]$issues.Add(("INF 无 HWID: {0}" -f $inf.Name)) }
        } catch {
            [void]$issues.Add(("INF 解析失败: {0}" -f $inf.Name))
        }
    }

    return [PSCustomObject]@{
        Ok       = ($issues.Count -eq 0)
        InfCount = $infs.Count
        Hwids    = @($hwidSet)
        Issues   = @($issues.ToArray())
    }
}

function Get-InferredPackageMeta {
    param(
        [string]$FolderName,
        [string]$PackageId,
        $FolderReport
    )

    $vendor = 'Unknown'
    $category = 'platform'
    $title = $FolderName

    $blob = ($FolderName + ' ' + $PackageId).ToLowerInvariant()
    if ($blob -match 'wifi|wireless') { $category = 'wifi' }
    elseif ($blob -match 'bluetooth') { $category = 'bluetooth' }
    elseif ($blob -match 'lan|ethernet|i219') { $category = 'lan' }
    elseif ($blob -match 'audio|sst|display_audio') { $category = 'audio' }
    elseif ($blob -match 'graphics|nvidia|gpu') { $category = 'gpu' }
    elseif ($blob -match 'chipset|platform|mei|serialio|rst|usb') { $category = 'chipset' }
    elseif ($blob -match 'touchpad|synaptics|elan') { $category = 'touchpad' }
    elseif ($blob -match 'printer|pcl|ufrii') { $category = 'printer' }
    elseif ($blob -match 'cardreader') { $category = 'storage' }

    if ($blob -match 'intel') { $vendor = 'Intel' }
    elseif ($blob -match 'realtek') { $vendor = 'Realtek' }
    elseif ($blob -match 'amd') { $vendor = 'AMD' }
    elseif ($blob -match 'nvidia') { $vendor = 'NVIDIA' }
    elseif ($blob -match 'synaptics') { $vendor = 'Synaptics' }
    elseif ($blob -match 'hp') { $vendor = 'HP' }
    elseif ($blob -match 'canon') { $vendor = 'Canon' }

    return [PSCustomObject]@{
        Title    = $title
        Vendor   = $vendor
        Category = $category
    }
}

function Find-ManifestPackageEntry {
    param(
        $Manifest,
        [string]$PackageId,
        [string]$ZipName
    )

    if (-not $Manifest -or -not $Manifest.packages) { return $null }

    foreach ($prop in $Manifest.packages.PSObject.Properties) {
        $pkg = $prop.Value
        $id = if ($pkg.id) { [string]$pkg.id } else { (Get-PackageIdentity -PackageKey $prop.Name -PackageRaw $pkg) }
        if ($id -eq $PackageId) {
            return [PSCustomObject]@{ Key = $prop.Name; Package = $pkg }
        }
        if ($pkg.url -and ([IO.Path]::GetFileName($pkg.url) -eq $ZipName)) {
            return [PSCustomObject]@{ Key = $prop.Name; Package = $pkg }
        }
    }
    return $null
}

function New-ManifestPackageTemplate {
    param(
        [string]$PackageId,
        [string]$ReleaseTag,
        [string]$Repo,
        $FolderReport,
        $Inferred
    )

    $zipName = "$PackageId.zip"
    $url = "https://github.com/$Repo/releases/download/$ReleaseTag/$zipName"
    return [PSCustomObject]@{
        id              = $PackageId
        url             = $url
        version         = ''
        sha256          = ''
        category        = $Inferred.Category
        vendor          = $Inferred.Vendor
        priority        = 50
        risk            = 'medium'
        signed          = $true
        whql            = $false
        reboot_required = $false
        title           = $Inferred.Title
        hwids           = @($FolderReport.Hwids | Select-Object -First 64)
        os              = @('win10', 'win11')
    }
}

function Invoke-BuildDriverRepository {
    param(
        [string]$ReleaseTag = 'v1.1.0',
        [string]$Repo = 'yanbai9188-oss/qudong',
        [string]$ManifestVersion = '',
        [string]$OutputDir = '',
        [switch]$DryRun,
        [switch]$AddNewPackages,
        [scriptblock]$OnLog
    )

    $root = Get-AppRoot
    $driversRoot = Join-Path $root 'Drivers'
    if (-not $OutputDir) { $OutputDir = Join-Path $root 'qudong-repo\packages' }
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null }

    $manifestPath = Join-Path $root 'driver_packages.json'
    if (-not (Test-Path $manifestPath)) { throw "缺少 manifest: $manifestPath" }
    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

    $log = {
        param($msg, [string]$Level = 'info')
        if ($OnLog) { & $OnLog $msg $Level }
        else { Write-Host $msg }
    }

    & $log '=== CIODIY Driver Repo Builder ===' 'info'
    & $log ("扫描目录: {0}" -f $driversRoot)

    $built = New-Object System.Collections.ArrayList
    $skipped = New-Object System.Collections.ArrayList
    $manifestUpdated = 0
    $manifestAdded = 0

    $folders = @(Get-ChildItem -Path $driversRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
    & $log ("发现驱动文件夹: {0}" -f $folders.Count)

    foreach ($dir in $folders) {
        if ($dir.Name -eq 'README.txt') { continue }
        $report = Test-DriverFolderReady -FolderPath $dir.FullName
        $packageId = Resolve-DriverPackageId -FolderName $dir.Name
        $zipName = "$packageId.zip"
        $zipPath = Join-Path $OutputDir $zipName

        if (-not $report.Ok) {
            [void]$skipped.Add([PSCustomObject]@{
                Folder = $dir.Name
                PackageId = $packageId
                Reason = ($report.Issues -join '; ')
            })
            & $log ("  跳过 {0}: {1}" -f $dir.Name, ($report.Issues -join '; ')) 'warn'
            continue
        }

        if ($DryRun) {
            [void]$built.Add([PSCustomObject]@{
                Folder = $dir.Name
                PackageId = $packageId
                ZipName = $zipName
                InfCount = $report.InfCount
                HwidCount = @($report.Hwids).Count
                Sha256 = '(dry-run)'
                SizeMb = 0
            })
            & $log ("  [dry-run] {0} -> {1} ({2} INF, {3} HWID)" -f $dir.Name, $zipName, $report.InfCount, @($report.Hwids).Count)
            continue
        }

        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        Compress-Archive -Path (Join-Path $dir.FullName '*') -DestinationPath $zipPath -Force
        $hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $sizeMb = [Math]::Round((Get-Item $zipPath).Length / 1MB, 2)

        [void]$built.Add([PSCustomObject]@{
            Folder    = $dir.Name
            PackageId = $packageId
            ZipName   = $zipName
            ZipPath   = $zipPath
            InfCount  = $report.InfCount
            HwidCount = @($report.Hwids).Count
            Sha256    = $hash
            SizeMb    = $sizeMb
        })
        & $log ("  打包 {0} ({1} MB) sha256={2}" -f $zipName, $sizeMb, $hash.Substring(0, 12) + '...')

        $entry = Find-ManifestPackageEntry -Manifest $manifest -PackageId $packageId -ZipName $zipName
        if ($entry) {
            $pkg = $entry.Package
            if ($pkg.sha256 -ne $hash) { $manifestUpdated++ }
            $pkg.sha256 = $hash
            $pkg.url = "https://github.com/$Repo/releases/download/$ReleaseTag/$zipName"
            if (-not $pkg.id) { $pkg | Add-Member -NotePropertyName id -NotePropertyValue $packageId -Force }
            if (@($report.Hwids).Count -gt 0 -and (-not $pkg.hwids -or @($pkg.hwids).Count -eq 0)) {
                $pkg.hwids = @($report.Hwids | Select-Object -First 64)
            }
        } elseif ($AddNewPackages) {
            $inferred = Get-InferredPackageMeta -FolderName $dir.Name -PackageId $packageId -FolderReport $report
            $newPkg = New-ManifestPackageTemplate -PackageId $packageId -ReleaseTag $ReleaseTag -Repo $Repo -FolderReport $report -Inferred $inferred
            $newPkg.sha256 = $hash
            $key = 'Auto_' + ($packageId -replace '[^a-zA-Z0-9_]', '_')
            $manifest.packages | Add-Member -NotePropertyName $key -NotePropertyValue $newPkg -Force
            $manifestAdded++
            & $log ("  新增 manifest 条目: {0}" -f $packageId) 'info'
        } else {
            & $log ("  警告: manifest 无条目 {0}，使用 -AddNewPackages 可自动添加" -f $packageId) 'warn'
        }
    }

    if (-not $DryRun) {
        if ($ManifestVersion) { $manifest.version = $ManifestVersion }
        $manifest.updated = (Get-Date -Format 'yyyy-MM-dd')
        if ($ReleaseTag) { $manifest.release = $ReleaseTag }

        $json = $manifest | ConvertTo-Json -Depth 14
        [System.IO.File]::WriteAllText($manifestPath, $json, [System.Text.UTF8Encoding]::new($false))

        $mirrorPaths = @(
            (Join-Path $root 'qudong-repo\manifest.json'),
            (Join-Path $root 'qudong-repo\driver_packages.json')
        )
        foreach ($mp in $mirrorPaths) {
            $parent = Split-Path $mp -Parent
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
            Copy-Item $manifestPath $mp -Force
        }
        & $log ("manifest 已更新: sha256 变更 {0}，新增 {1}" -f $manifestUpdated, $manifestAdded) 'info'
    }

    return [PSCustomObject]@{
        Built            = @($built.ToArray())
        Skipped          = @($skipped.ToArray())
        ManifestPath     = $manifestPath
        OutputDir        = $OutputDir
        ManifestUpdated  = $manifestUpdated
        ManifestAdded    = $manifestAdded
        ReleaseTag       = $ReleaseTag
        DryRun           = [bool]$DryRun
    }
}

function Write-DriverRepoBuildReport {
    param(
        [Parameter(Mandatory)]$Result,
        [string]$Path = ''
    )

    if (-not $Path) {
        $logs = Join-Path (Get-AppDataRoot) 'Logs'
        if (-not (Test-Path $logs)) { New-Item -ItemType Directory -Force -Path $logs | Out-Null }
        $Path = Join-Path $logs ("RepoBuild_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    }

    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('CIODIY Driver Repo Builder Report')
    [void]$lines.Add(('Time: {0}' -f (Get-Date -Format 'o')))
    [void]$lines.Add(('Release: {0}' -f $Result.ReleaseTag))
    [void]$lines.Add(('Built: {0}  Skipped: {1}' -f $Result.Built.Count, $Result.Skipped.Count))
    [void]$lines.Add('')
    [void]$lines.Add('--- Packaged ---')
    foreach ($b in @($Result.Built)) {
        [void]$lines.Add(('{0,-30} {1,8} MB  INF={2}  HWID={3}' -f $b.ZipName, $b.SizeMb, $b.InfCount, $b.HwidCount))
    }
    if ($Result.Skipped.Count -gt 0) {
        [void]$lines.Add('')
        [void]$lines.Add('--- Skipped ---')
        foreach ($s in @($Result.Skipped)) {
            [void]$lines.Add(('{0}: {1}' -f $s.Folder, $s.Reason))
        }
    }

    ($lines -join [Environment]::NewLine) | Set-Content $Path -Encoding UTF8
    return $Path
}
