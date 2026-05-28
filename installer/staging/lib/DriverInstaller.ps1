# Install drivers with transaction support (backup -> install -> verify -> commit)

function Install-InfDrivers {
    param(
        [Parameter(Mandatory)][string]$Folder,
        [scriptblock]$OnLog
    )

    $pattern = Join-Path $Folder '*.inf'
    Write-AppLog "pnputil install INF: $Folder" -OnLog $OnLog
    $output = & pnputil.exe /add-driver $pattern /subdirs /install 2>&1
    foreach ($line in $output) { Write-AppLog "pnputil: $line" -OnLog $OnLog }
    & pnputil.exe /scan-devices 2>&1 | ForEach-Object { Write-AppLog "pnputil: $_" -OnLog $OnLog }
}

function Install-MsiPackage {
    param(
        [Parameter(Mandatory)][string]$MsiPath,
        [scriptblock]$OnLog
    )

    Write-AppLog "Silent MSI install: $MsiPath" -OnLog $OnLog
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', "`"$MsiPath`"", '/qn', '/norestart') -Wait -PassThru -NoNewWindow
    Write-AppLog "msiexec exit: $($proc.ExitCode)" -OnLog $OnLog
    return ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010)
}

function Install-ExeSilent {
    param(
        [Parameter(Mandatory)][string]$ExePath,
        [string[]]$SilentArgs = @('/S', '/silent', '/quiet', '-silent', '-quiet'),
        [scriptblock]$OnLog
    )

    Write-AppLog "Silent EXE install: $ExePath" -OnLog $OnLog
    $lastExit = -1
    foreach ($arg in $SilentArgs) {
        try {
            $proc = Start-Process -FilePath $ExePath -ArgumentList $arg -Wait -PassThru -NoNewWindow
            $lastExit = $proc.ExitCode
            Write-AppLog "EXE exit $lastExit (arg: $arg)" -OnLog $OnLog
            if ($lastExit -eq 0 -or $lastExit -eq 3010) {
                Write-AppLog "Install OK" -OnLog $OnLog
                return $true
            }
            # Stop trying further args once the process actually ran (non-exception)
            break
        } catch {
            Write-AppLog "Launch failed with arg '$arg': $($_.Exception.Message)" -OnLog $OnLog
        }
    }
    Write-AppLog "EXE install may have failed (last exit: $lastExit)" -OnLog $OnLog
    return ($lastExit -eq 0 -or $lastExit -eq 3010)
}

function Install-DriverFolder {
    param(
        [Parameter(Mandatory)][string]$Folder,
        [string]$InstallType = 'inf',
        [scriptblock]$OnLog
    )

    if (-not (Test-Path $Folder)) { throw "Driver folder not found: $Folder" }

    $msi = Get-ChildItem -Path $Folder -Filter 'SetupChipset.msi' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($msi) {
        if (-not (Install-MsiPackage -MsiPath $msi.FullName -OnLog $OnLog)) { throw 'MSI install failed' }
    }

    $setupChipsetExe = Get-ChildItem -Path $Folder -Filter 'SetupChipset.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($setupChipsetExe -and -not $msi) {
        if (-not (Install-ExeSilent -ExePath $setupChipsetExe.FullName -SilentArgs @('/exenoui', '/qn', '/norestart') -OnLog $OnLog)) {
            throw 'Chipset EXE install failed'
        }
    }

    if ($InstallType -eq 'exe_silent') {
        $exe = Get-ChildItem -Path $Folder -Filter '*.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($exe) {
            if (-not (Install-ExeSilent -ExePath $exe.FullName -OnLog $OnLog)) { throw 'EXE install failed' }
        }
    }

    $infs = Get-ChildItem -Path $Folder -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue
    if ($infs) {
        Install-InfDrivers -Folder $Folder -OnLog $OnLog
    }

    return $true
}

function Invoke-FixPlanItemInstall {
    param(
        [Parameter(Mandatory)]$Item,
        [scriptblock]$OnLog,
        [scriptblock]$OnProgress
    )

    $dev = $Item.Device
    switch ($Item.Action) {
        'InstallLocal' {
            Install-DriverFolder -Folder $Item.Package.LocalPath -InstallType $Item.Package.InstallType -OnLog $OnLog
        }
        'DownloadThenInstall' {
            $path = Download-DriverPackage -Package $Item.Package -PackageId $Item.Package.PackageId -OnLog $OnLog -OnProgress $OnProgress
            Install-DriverFolder -Folder $path -InstallType $Item.Package.InstallType -OnLog $OnLog
        }
        'CatalogSearch' {
            $hw = if ($dev.HardwareIds.Count -gt 0) { $dev.HardwareIds[0] } else { $dev.InstanceId }
            $catName = 'catalog_' + ($hw -replace '[\\/:*?"<>|&]', '_').Substring(0, [Math]::Min(40, $hw.Length))
            $catDir = Join-Path (Join-Path (Get-AppRoot) 'Drivers') $catName
            $downloaded = Download-CatalogDriver -HardwareId $hw -DestDir $catDir -OnLog $OnLog
            if (-not $downloaded) {
                $url = Get-CatalogSearchUrl -HardwareId $hw
                throw "Catalog 下载失败，请手动下载: $url"
            }
            Install-DriverFolder -Folder $downloaded -OnLog $OnLog
        }
        default {
            $hw = if ($dev.HardwareIds.Count -gt 0) { $dev.HardwareIds[0] } else { '' }
            throw "无可用安装源，请手动: $(Get-CatalogSearchUrl -HardwareId $hw)"
        }
    }
}

function Invoke-FixPlan {
    param(
        [Parameter(Mandatory)][array]$FixPlan,
        [switch]$CreateRestorePoint,
        [switch]$BackupFirst,
        [switch]$RollbackOnError,
        [switch]$VerifyInstall,
        [scriptblock]$OnLog,
        [scriptblock]$OnProgress,
        [scriptblock]$OnItemDone
    )

    Assert-Admin
    if ($VerifyInstall -eq $false -and $PSBoundParameters.ContainsKey('VerifyInstall') -eq $false) {
        $VerifyInstall = $true
    }

    if ($CreateRestorePoint) {
        Write-AppLog '正在创建系统还原点...' -OnLog $OnLog
        $rp = New-SystemRestorePoint -Description 'CIODIY Driver Fix'
        Write-AppLog $rp.Message -OnLog $OnLog
        if ($rp.Detail -and -not $rp.Success) {
            Write-AppLog ("还原点详情: {0}" -f $rp.Detail) -OnLog $OnLog
        }
    }

    $tx = Start-DriverTransaction -FixPlan $FixPlan -RollbackOnError:$RollbackOnError -OnLog $OnLog
    $total = $FixPlan.Count
    $idx = 0
    $rebootNeeded = $false
    $results = New-Object System.Collections.ArrayList
    $committedSteps = New-Object System.Collections.ArrayList
    $txFailed = $false

    foreach ($item in $FixPlan) {
        $idx++
        $pct = [int](($idx - 1) / [Math]::Max($total, 1) * 100)
        if ($OnProgress) { & $OnProgress $pct $item.Device.FriendlyName }

        $dev = $item.Device
        $pkgId = if ($item.Package) { $item.Package.Id } else { '' }
        Write-AppLog ("[{0}/{1}] tx step: {2}" -f $idx, $total, $dev.FriendlyName) -OnLog $OnLog

        $backupPath = $null
        $stepOk = $false
        $verified = $false
        $errMsg = ''

        try {
            if ($BackupFirst -or $RollbackOnError) {
                $backupPath = Backup-DeviceDriver -InstanceId $dev.InstanceId -FriendlyName $dev.FriendlyName -OnLog $OnLog
                Complete-TransactionStep -Transaction $tx -Device $dev -Package $item.Package -Phase 'backup' `
                    -BackupPath $backupPath -StepIndex $idx -PackageId $pkgId | Out-Null
            }

            Invoke-FixPlanItemInstall -Item $item -OnLog $OnLog -OnProgress {
                param($pct, $label)
                if ($OnProgress) { & $OnProgress $pct $label }
            }
            if ($item.Package -and $item.Package.RebootRequired) { $rebootNeeded = $true }

            $afterVer = Get-DeviceDriverVersion -InstanceId $dev.InstanceId
            Complete-TransactionStep -Transaction $tx -Device $dev -Package $item.Package -Phase 'install' `
                -BackupPath $backupPath -AfterVersion $afterVer -StepIndex $idx -PackageId $pkgId | Out-Null

            if ($VerifyInstall) {
                $v = Test-DriverInstall -Device $dev -Package $item.Package -OnLog $OnLog
                $verified = [bool]$v.verified
                Complete-TransactionStep -Transaction $tx -Device $dev -Package $item.Package -Phase 'verify' `
                    -BackupPath $backupPath -AfterVersion $afterVer -Verified $verified -StepIndex $idx -PackageId $pkgId | Out-Null

                if (-not $verified) {
                    throw 'Post-install verification failed'
                }
            } else {
                $verified = $true
            }

            Complete-TransactionStep -Transaction $tx -Device $dev -Package $item.Package -Phase 'commit' `
                -BackupPath $backupPath -AfterVersion $afterVer -Verified $verified -StepIndex $idx -PackageId $pkgId | Out-Null

            [void]$committedSteps.Add($idx)
            $stepOk = $true
            [void]$results.Add([PSCustomObject]@{
                Device    = $dev.FriendlyName
                Success   = $true
                Action    = $item.Action
                Verified  = $verified
                Score     = $item.Score
                PackageId = $pkgId
                TxId      = $tx.Id
            })
        } catch {
            $errMsg = $_.Exception.Message
            Write-AppLog "Step failed: $errMsg" -OnLog $OnLog
            Complete-TransactionStep -Transaction $tx -Device $dev -Package $item.Package -Phase 'rollback' `
                -BackupPath $backupPath -StepIndex $idx -PackageId $pkgId -ErrorMessage $errMsg | Out-Null

            [void]$results.Add([PSCustomObject]@{
                Device    = $dev.FriendlyName
                Success   = $false
                Action    = $item.Action
                Error     = $errMsg
                PackageId = $pkgId
                TxId      = $tx.Id
            })

            if ($RollbackOnError) {
                Write-AppLog 'RollbackOnError: rolling back transaction...' -OnLog $OnLog
                Invoke-DriverTransactionRollback -Transaction $tx -OnLog $OnLog | Out-Null
                $txFailed = $true
                break
            }
        }

        if ($OnItemDone) { & $OnItemDone $item $results[-1] }
    }

    if ($OnProgress) { & $OnProgress 100 '完成' }

    $finalStatus = if ($txFailed) { 'rolled_back' } elseif (@($results | Where-Object { -not $_.Success }).Count -gt 0) { 'failed' } else { 'committed' }
    Close-DriverTransaction -Transaction $tx -FinalStatus $finalStatus -OnLog $OnLog
    Write-InstallStatBatch -Results @($results.ToArray()) -TransactionId $tx.Id -FinalStatus $finalStatus

    return [PSCustomObject]@{
        Results       = @($results.ToArray())
        RebootNeeded  = $rebootNeeded
        TransactionId = $tx.Id
        TxDirectory   = $tx.Directory
        FinalStatus   = $finalStatus
        RolledBack    = $txFailed
    }
}

function Install-AllLocalDrivers {
    param(
        [scriptblock]$OnLog,
        [switch]$RollbackOnError
    )

    Assert-Admin
    $root = Join-Path (Get-AppRoot) 'Drivers'
    if (-not (Test-Path $root)) { return }

    $plan = New-Object System.Collections.ArrayList
    foreach ($dir in Get-ChildItem -Path $root -Directory) {
        $hasDriver = Get-ChildItem -Path $dir.FullName -Include '*.inf', '*.msi', '*.exe' -Recurse -ErrorAction SilentlyContinue
        if (-not $hasDriver) { continue }
        $fakeDev = [PSCustomObject]@{
            FriendlyName  = $dir.Name
            InstanceId    = 'LOCAL\' + $dir.Name
            HardwareIds   = @()
            DriverVersion = ''
            Status        = 'Unknown'
            IsProblem     = $true
        }
        $pkg = ConvertTo-PackageCandidate -PackageKey ('Local_' + $dir.Name) -PackageRaw ([PSCustomObject]@{
            id = $dir.Name; title = $dir.Name; local_only = $true
        }) -Device $fakeDev
        $pkg.LocalPath = $dir.FullName
        [void]$plan.Add([PSCustomObject]@{
            Device = $fakeDev; Package = $pkg; Action = 'InstallLocal'; Score = 80
        })
    }

    if ($plan.Count -eq 0) { return }
    return Invoke-FixPlan -FixPlan @($plan.ToArray()) -BackupFirst -RollbackOnError:$RollbackOnError -OnLog $OnLog
}
