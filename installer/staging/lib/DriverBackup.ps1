# Driver backup before installation

function Backup-DeviceDriver {
    param(
        [Parameter(Mandatory)][string]$InstanceId,
        [Parameter(Mandatory)][string]$FriendlyName,
        [scriptblock]$OnLog
    )

    $backupRoot = Join-Path (Get-AppDataRoot) 'DriverBackup'
    $safeName = ($FriendlyName -replace '[\\/:*?"<>|]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'device' }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dest = Join-Path $backupRoot "${stamp}_${safeName}"

    New-Item -ItemType Directory -Force -Path $dest | Out-Null

    try {
        $published = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_Device_DriverInfPath' -ErrorAction Stop
        $infPath = [string]$published.Data
        if ($infPath -and (Test-Path $infPath)) {
            $publishedName = Split-Path $infPath -Leaf
            $exportOut = Join-Path $dest 'export'
            New-Item -ItemType Directory -Force -Path $exportOut | Out-Null
            $output = & pnputil.exe /export-driver $publishedName $exportOut 2>&1
            foreach ($line in $output) { Write-AppLog "backup: $line" -OnLog $OnLog }
            Set-Content -Path (Join-Path $dest 'backup_info.txt') -Value @(
                "Device: $FriendlyName",
                "InstanceId: $InstanceId",
                "InfPath: $infPath",
                "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            ) -Encoding UTF8
            Write-AppLog "Backed up: $FriendlyName -> $dest" -OnLog $OnLog
            return $dest
        }
    } catch {
        Write-AppLog "Skip backup (no published driver): $FriendlyName" -OnLog $OnLog
    }
    return $null
}

function Backup-AllProblemDrivers {
    param(
        [Parameter(Mandatory)][array]$ScanResults,
        [scriptblock]$OnLog
    )

    $backups = @()
    foreach ($dev in ($ScanResults | Where-Object { $_.IsProblem })) {
        $b = Backup-DeviceDriver -InstanceId $dev.InstanceId -FriendlyName $dev.FriendlyName -OnLog $OnLog
        if ($b) { $backups += $b }
    }
    return $backups
}
