# Offline driver workflow: export request / import pack (v1.8)

function Export-HardwareDriverRequest {
    param(
        [string]$OutputPath = '',
        [scriptblock]$OnLog
    )

    if ($OnLog) { & $OnLog 'Scanning and exporting hardware request...' }
    $scan = @(Invoke-DriverScanEngine -OnLog $OnLog)
    $manifest = Get-EngineManifest
    $match = Invoke-DriverMatchEngine -ScanResults $scan -Manifest $manifest -OnLog $OnLog -SkipLocalIndex
    $hw = Get-HardwareProfile
    $os = Get-SystemOsProfile

    $requests = @($match.FixPlan | ForEach-Object {
        $view = ConvertTo-CIODIYFixPlanItem -InternalItem $_
        [PSCustomObject]@{
            deviceKey     = $view.DeviceKey
            deviceId      = $view.DeviceId
            displayName   = $view.DisplayName
            deviceClass   = $view.DeviceClass
            packageId     = $view.PackageId
            packageName   = $view.PackageName
            action        = $_.Action
            targetVersion = $view.Raw.TargetVersion
            hwids         = @($_.Device.HardwareIds)
        }
    })

    $obj = [PSCustomObject]@{
        schema       = 'hardware_request_v1'
        exported_at  = (Get-Date -Format 'o')
        machine      = $hw.MachineTitle
        platform     = $hw.PlatformLine
        os           = $os.Label
        build        = $os.Build
        manifest_ver = if ($manifest) { $manifest.version } else { '' }
        items        = $requests
    }

    if (-not $OutputPath) {
        $OutputPath = Join-Path (Get-AppDataRoot) ('hardware_request_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    }
    $dir = Split-Path $OutputPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    ($obj | ConvertTo-Json -Depth 8) | Set-Content $OutputPath -Encoding UTF8

    if ($OnLog) { & $OnLog ("Exported: $OutputPath ($($requests.Count) items)") }
    return New-CIODIYOperationResult -Success $true -Code 'OK' -Data $obj -Message $OutputPath
}

function Import-OfflineDriverPack {
    param(
        [Parameter(Mandatory)][string]$PackPath,
        [scriptblock]$OnLog
    )

    if (-not (Test-Path $PackPath)) {
        return New-CIODIYOperationResult -Success $false -Code 'NOT_FOUND' -Message 'Offline pack not found'
    }

    $destRoot = Join-Path (Get-AppRoot) 'Drivers'
    if (-not (Test-Path $destRoot)) { New-Item -ItemType Directory -Force -Path $destRoot | Out-Null }

    if ($PackPath -like '*.zip') {
        $temp = Join-Path (Get-AppDataRoot) ('Cache\offline_import_{0}' -f (Get-Date -Format 'yyyyMMddHHmmss'))
        New-Item -ItemType Directory -Force -Path $temp | Out-Null
        Expand-Archive -Path $PackPath -DestinationPath $temp -Force
        Copy-Item (Join-Path $temp '*') $destRoot -Recurse -Force
        Remove-Item $temp -Recurse -Force -EA SilentlyContinue
    } else {
        Copy-Item $PackPath $destRoot -Recurse -Force
    }

    if ($OnLog) { & $OnLog "Offline pack imported: $PackPath" }
    return New-CIODIYOperationResult -Success $true -Code 'OK' -Message 'Offline pack import complete'
}
