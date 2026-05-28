# Manifest v3: depends, conflicts, blacklist, install order

function Get-PackageIdentity {
    param(
        [string]$PackageKey,
        $PackageRaw
    )
    if ($PackageRaw.id) { return [string]$PackageRaw.id }
    return ($PackageKey -replace '^Seed_', '')
}

function Test-VersionBlacklisted {
    param(
        [string]$InstalledVersion,
        [array]$Blacklist
    )
    if (-not $Blacklist -or -not $InstalledVersion) { return $false }
    foreach ($bad in @($Blacklist)) {
        if ($InstalledVersion -like "*$bad*") { return $true }
    }
    return $false
}

function Test-PackageConflict {
    param(
        [string]$PackageId,
        [array]$Conflicts,
        [string[]]$ActivePackageIds
    )
    if (-not $Conflicts -or $ActivePackageIds.Count -eq 0) { return $false }
    foreach ($conflict in @($Conflicts)) {
        if ($ActivePackageIds -contains $conflict) { return $true }
        if ($PackageId -eq $conflict) { return $true }
    }
    return $false
}

function Resolve-FixPlanOrder {
    param(
        [Parameter(Mandatory)][array]$FixPlan,
        [hashtable]$Packages
    )

    if ($FixPlan.Count -le 1) { return $FixPlan }

    $items = @($FixPlan | ForEach-Object {
        $pkgId = if ($_.Package) { $_.Package.Id } else { '' }
        $depends = @()
        $order = 50
        if ($_.Package) {
            if ($_.Package.Depends) { $depends = @($_.Package.Depends) }
            if ($null -ne $_.Package.InstallOrder) { $order = [int]$_.Package.InstallOrder }
        }
        [PSCustomObject]@{
            Item    = $_
            Id      = $pkgId
            Depends = $depends
            Order   = $order
        }
    })

    $sorted = New-Object System.Collections.ArrayList
    $remaining = [System.Collections.Generic.List[object]]::new()
    foreach ($i in $items) { [void]$remaining.Add($i) }

    $guard = 0
    while ($remaining.Count -gt 0 -and $guard -lt 1000) {
        $guard++
        $ready = @($remaining | Where-Object {
            $depOk = $true
            foreach ($d in @($_.Depends)) {
                if ([string]::IsNullOrWhiteSpace($d)) { continue }
                $installed = @($sorted | ForEach-Object { $_.Id }) -contains $d
                $inPlan = @($items | ForEach-Object { $_.Id }) -contains $d
                if ($inPlan -and -not $installed) { $depOk = $false; break }
            }
            $depOk
        } | Sort-Object Order, { $_.Id })

        if ($ready.Count -eq 0) {
            foreach ($r in ($remaining | Sort-Object Order)) { [void]$sorted.Add($r) }
            break
        }

        foreach ($r in $ready) {
            [void]$sorted.Add($r)
            [void]$remaining.Remove($r)
        }
    }

    return @($sorted | ForEach-Object { $_.Item })
}

function Expand-FixPlanDependencies {
    param(
        [Parameter(Mandatory)][array]$FixPlan,
        [hashtable]$Packages,
        $Manifest,
        [array]$ScanResults = @()
    )

    $existingIds = @($FixPlan | ForEach-Object { if ($_.Package) { $_.Package.Id } })
    $extra = New-Object System.Collections.ArrayList

    foreach ($item in $FixPlan) {
        if (-not $item.Package -or -not $item.Package.Depends) { continue }
        foreach ($depId in @($item.Package.Depends)) {
            if ($existingIds -contains $depId) { continue }
            foreach ($key in $Packages.Keys) {
                $raw = $Packages[$key]
                $id = Get-PackageIdentity -PackageKey $key -PackageRaw $raw
                if ($id -ne $depId) { continue }

                $candidate = ConvertTo-PackageCandidate -PackageKey $key -PackageRaw $raw -Device $item.Device
                $depDevice = Find-DependencyDevice -DepPackage $candidate -ScanResults $ScanResults

                Resolve-PackageLocalPath -Package $candidate | Out-Null
                $action = if ($candidate.LocalPath) { 'InstallLocal' }
                          elseif ($candidate.Url) { 'DownloadThenInstall' }
                          else { 'CatalogSearch' }

                $depKey = if ($depDevice.MergeKey) { $depDevice.MergeKey } else { Get-CIODIYDeviceKey -Device $depDevice }
                [void]$extra.Add([PSCustomObject]@{
                    Device         = $depDevice
                    Package        = $candidate
                    Action         = $action
                    CurrentVersion = if ($depDevice.DriverVersion) { $depDevice.DriverVersion } else { '' }
                    TargetVersion  = $candidate.Version
                    NeedsUpdate    = $true
                    IsOutdated     = $false
                    IsDependency   = $true
                    ParentPackageId = if ($item.Package) { [string]$item.Package.Id } else { '' }
                    MergeKey       = $depKey
                    ExactHwidMatch = Test-ExactHwidMatch -Device $depDevice -PatternIds @($raw.hwids)
                })
                $existingIds += $depId
                break
            }
        }
    }

    if ($extra.Count -eq 0) { return $FixPlan }
    $merged = @($extra.ToArray()) + @($FixPlan)
    return @(Resolve-FixPlanOrder -FixPlan $merged -Packages $Packages)
}

function Resolve-PackageLocalPath {
    param([Parameter(Mandatory)]$Package)

    $localRoot = Join-Path (Get-AppRoot) 'Drivers'
    $candidates = @(
        (Join-Path $localRoot $Package.PackageId)
        (Join-Path $localRoot ($Package.PackageId -replace '^Seed_', ''))
        (Join-Path $localRoot $Package.Id)
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $Package.LocalPath = $c; return $Package }
    }

    $map = @{
        'intel_chipset'     = 'intel_chipset'
        'Intel_Chipset_INF' = 'intel_chipset'
        'intel_serialio'    = 'intel_serialio'
        'intel_bluetooth'   = 'intel_bluetooth'
        'intel_wifi'        = 'intel_wifi'
        'intel_wifi_7260'   = 'Intel_7260_WiFi_16.10.0.5'
        'intel_mei'         = 'intel_mei'
        'intel_rst'         = 'intel_rst'
        'intel_dtt'         = 'intel_dtt'
        'intel_sst'         = 'intel_sst'
        'intel_platform'    = 'intel_platform'
        'intel_graphics'    = 'intel_graphics'
        'intel_usb3'        = 'intel_usb3'
        'intel_lan_i219'    = 'intel_lan_i219'
        'intel_wifi_8260'   = 'intel_wifi_8260'
        'realtek_cardreader' = 'realtek_cardreader'
        'realtek_lan'       = 'realtek_lan'
        'Realtek_LAN_8168'  = 'Realtek_LAN_8168'
        'Intel_DisplayAudio' = 'Intel_DisplayAudio'
        'realtek_audio'     = 'realtek_audio'
        'amd_chipset'       = 'amd_chipset'
    }
    foreach ($key in @($Package.Id, ($Package.PackageId -replace '^Seed_', ''))) {
        if ($map.ContainsKey($key)) {
            $folder = Join-Path $localRoot $map[$key]
            if (Test-Path $folder) { $Package.LocalPath = $folder; return $Package }
        }
    }
    return $Package
}
