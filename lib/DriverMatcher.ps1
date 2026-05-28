# Match devices to driver packages (scoring-based)

function Get-LocalManifestPath {
    if (Get-Command Get-LocalManifestPathForChannel -ErrorAction SilentlyContinue) {
        $channelPath = Get-LocalManifestPathForChannel
        if ($channelPath) { return $channelPath }
    }
    $root = Get-AppRoot
    $data = Get-AppDataRoot
    $paths = @(
        (Join-Path $data 'driver_packages.json'),
        (Join-Path $root 'driver_packages.json'),
        (Join-Path (Join-Path $data 'Cache') 'manifest.json'),
        (Join-Path (Join-Path $root 'Cache') 'manifest.json'),
        (Join-Path (Join-Path $root 'driver-mirror-repo') 'manifest.json')
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Import-DriverManifest {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return $null }
    return Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-ManifestPackages {
    param($Manifest)
    if (-not $Manifest -or -not $Manifest.packages) { return @{} }
    $dict = @{}
    foreach ($prop in $Manifest.packages.PSObject.Properties) {
        $dict[$prop.Name] = $prop.Value
    }
    return $dict
}

function Get-InfHardwareIds {
    param([Parameter(Mandatory)][string]$InfPath)
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-Content -Path $InfPath -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*[;#]') { continue }
        foreach ($m in [regex]::Matches($line, '(PCI|USB|HDAUDIO|ACPI|SWD|ROOT|SCSI|SPSVC|MF|BIOM)\\[^;\s"]+')) {
            $ids.Add($m.Value.Trim('"'))
        }
    }
    return @($ids | Select-Object -Unique)
}

function Get-CandidatePackages {
    param(
        [Parameter(Mandatory)]$Device,
        [hashtable]$Packages,
        [string[]]$ActivePackageIds = @()
    )

    $candidates = New-Object System.Collections.ArrayList

    foreach ($key in $Packages.Keys) {
        $raw = $Packages[$key]
        $hwids = @()
        if ($raw.hwids) { $hwids = @($raw.hwids) }
        if (-not (Test-HardwareIdMatch -DeviceIds $Device.HardwareIds -PatternIds $hwids)) { continue }
        if (-not (Test-DevicePackageAllowed -Device $Device -PackageRaw $raw -MatchHwids $hwids)) { continue }

        $id = Get-PackageIdentity -PackageKey $key -PackageRaw $raw
        if (Test-VersionBlacklisted -InstalledVersion $Device.DriverVersion -Blacklist @($raw.blacklist)) { continue }
        if (Test-PackageConflict -PackageId $id -Conflicts @($raw.conflicts) -ActivePackageIds $ActivePackageIds) { continue }

        $c = ConvertTo-PackageCandidate -PackageKey $key -PackageRaw $raw -Device $Device
        if (-not (Test-PackageOsCompatible -Package $c)) { continue }
        $c | Add-Member -NotePropertyName _MatchHwids -NotePropertyValue $hwids -Force
        Resolve-PackageLocalPath -Package $c | Out-Null
        [void]$candidates.Add($c)
    }

    $local = $null
    if ($script:UseLocalInfIndex) {
        $local = Find-LocalDriverByHardwareId -DeviceIds $Device.HardwareIds
    }
    if ($local) {
        $devClass = Get-CIODIYDeviceClass -Device $Device
        $localOk = (Test-DeviceClassCompatible -Device $Device -Package $local) -and (
            ($devClass -ne 'unknown') -or (Test-ExactHwidMatch -Device $Device -PatternIds @($local._MatchHwids))
        )
        if ($localOk) {
            $exists = @($candidates | Where-Object { $_.LocalPath -eq $local.LocalPath })
            if ($exists.Count -eq 0) { [void]$candidates.Add($local) }
        }
    }

    return @($candidates.ToArray())
}

function Find-MatchingPackage {
    param(
        [Parameter(Mandatory)]$Device,
        [hashtable]$Packages,
        [string[]]$ActivePackageIds = @()
    )

    $candidates = Get-CandidatePackages -Device $Device -Packages $Packages -ActivePackageIds $ActivePackageIds
    if ($candidates.Count -eq 0) { return $null }
    return Select-BestScoredCandidate -Candidates $candidates -Device $Device -InstalledPackageIds $ActivePackageIds
}

function Build-DriverFixPlan {
    param(
        [Parameter(Mandatory)][array]$ScanResults,
        $Manifest
    )

    $ScanResults = Merge-ScanDevices -Devices $ScanResults
    $packages = Get-ManifestPackages -Manifest $Manifest
    $plan = New-Object System.Collections.ArrayList
    $activeIds = New-Object System.Collections.ArrayList

    foreach ($device in $ScanResults) {
        if (-not $device.HardwareIds -or @($device.HardwareIds).Count -eq 0) { continue }

        $match = Find-MatchingPackage -Device $device -Packages $packages -ActivePackageIds @($activeIds)
        $needsFix = [bool]$device.IsProblem
        $isOutdated = $false

        if (-not $needsFix -and $match -and $match.Version) {
            $cmp = Compare-DriverVersion -Installed $device.DriverVersion -Available $match.Version
            if ($cmp -lt 0) {
                $needsFix = $true
                $isOutdated = $true
            }
        }

        if (-not $needsFix) { continue }

        $action = if ($match) {
            if ($match.LocalPath) { 'InstallLocal' }
            elseif ($match.Sources -and @($match.Sources).Count -gt 0) { 'DownloadThenInstall' }
            elseif ($match.Url) { 'DownloadThenInstall' }
            elseif ($match.LocalOnly) { 'CatalogSearch' }
            else { 'CatalogSearch' }  # No static source -> try catalog
        } else { 'CatalogSearch' }

        if ($match -and $match.Id) { [void]$activeIds.Add($match.Id) }

        $mergeKey = if ($device.MergeKey) { $device.MergeKey } else { Get-CIODIYDeviceKey -Device $device }
        [void]$plan.Add([PSCustomObject]@{
            Device            = $device
            Package           = $match
            Action            = $action
            CurrentVersion    = $device.DriverVersion
            TargetVersion     = if ($match) { $match.Version } else { '' }
            NeedsUpdate       = $true
            IsOutdated        = $isOutdated
            ConfidencePercent = if ($match) { $match.ConfidencePercent } else { 0 }
            ConfidenceLabel   = if ($match) { $match.ConfidenceLabel } else { 'none' }
            Score             = if ($match) { $match.Score } else { 0 }
            MergeKey          = $mergeKey
            ExactHwidMatch    = if ($match -and $match._MatchHwids) {
                Test-ExactHwidMatch -Device $device -PatternIds @($match._MatchHwids)
            } else { $false }
        })
    }

    $ordered = Expand-FixPlanDependencies -FixPlan @($plan.ToArray()) -Packages $packages -Manifest $Manifest -ScanResults $ScanResults
    $ordered = Finalize-FixPlanDisplay -FixPlan $ordered
    return @(Resolve-FixPlanOrder -FixPlan $ordered -Packages $packages)
}
