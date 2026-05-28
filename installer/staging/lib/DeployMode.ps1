# Deploy mode — batch reinstall automation (v1.4.0)

function Test-FixPlanItemRecommended {
    param($Item)

    if (-not $Item -or $Item.Action -in @('NoSource', 'CatalogSearch')) { return $false }
    $tier = Get-RecommendTier -Item $Item
    return (Test-RecommendTierAutoSelect -Tier $tier)
}

function Select-RecommendedFixPlan {
    param([array]$FixPlan)
    return @($FixPlan | Where-Object { Test-FixPlanItemRecommended -Item $_ })
}

function Get-DeployIssueLabel {
    param($Item)
    if (-not $Item) { return '-' }
    $dev = $Item.Device
    if ($Item.IsOutdated) { return '版本过旧' }
    if ($dev.IsProblem -or [string]$dev.Status -match 'Error|Problem|Unknown') {
        if ([string]::IsNullOrWhiteSpace($dev.DriverVersion)) { return '未安装' }
        return '设备异常'
    }
    return '推荐更新'
}

function Build-DeployMissingList {
    param([array]$FixPlan)

    $list = New-Object System.Collections.ArrayList
    foreach ($item in @($FixPlan)) {
        $pkgTitle = if ($item.Package -and $item.Package.Title) { $item.Package.Title } else { '(无包)' }
        [void]$list.Add([PSCustomObject]@{
            Device  = [string]$item.Device.FriendlyName
            Package = $pkgTitle
            Issue   = (Get-DeployIssueLabel -Item $item)
        })
    }
    return @($list.ToArray())
}

function Build-DeployInstallLines {
    param($InstallResult, [array]$FixPlan)

    $lines = New-Object System.Collections.ArrayList
    if ($InstallResult -and $InstallResult.Results) {
        foreach ($r in @($InstallResult.Results)) {
            $pkg = @($FixPlan | Where-Object { $_.Device.FriendlyName -eq $r.Device } | Select-Object -First 1)
            $pkgTitle = if ($pkg -and $pkg.Package -and $pkg.Package.Title) { $pkg.Package.Title } else { $r.PackageId }
            [void]$lines.Add([PSCustomObject]@{
                Device  = [string]$r.Device
                Package = [string]$pkgTitle
                Success = [bool]$r.Success
                Error   = if ($r.Error) { [string]$r.Error } else { '' }
            })
        }
        return @($lines.ToArray())
    }

    foreach ($item in @($FixPlan)) {
        [void]$lines.Add([PSCustomObject]@{
            Device  = [string]$item.Device.FriendlyName
            Package = if ($item.Package) { $item.Package.Title } else { '' }
            Success = $false
            Error   = '未执行'
        })
    }
    return @($lines.ToArray())
}

function Resolve-DeployStatus {
    param(
        $InstallResult,
        [int]$SelectedCount,
        [int]$FixPlanCount = 0,
        [switch]$AutoFix
    )

    if (-not $AutoFix) {
        if ($FixPlanCount -eq 0) { return 'no_action' }
        return 'scan_only'
    }
    if ($SelectedCount -eq 0) { return 'no_action' }
    if (-not $InstallResult) { return 'failed' }
    if ($InstallResult.RolledBack) { return 'rolled_back' }
    if ($InstallResult.FinalStatus -eq 'committed') { return 'success' }

    $ok = @($InstallResult.Results | Where-Object { $_.Success }).Count
    $total = @($InstallResult.Results).Count
    if ($ok -gt 0 -and $ok -lt $total) { return 'partial' }
    return 'failed'
}

function Invoke-DeployReboot {
    param(
        [int]$DelaySec = 60,
        [switch]$Force
    )

    if ($Force) {
        Restart-Computer -Force
        return
    }
    Start-Process -FilePath 'shutdown.exe' -ArgumentList @('/r', '/t', [string]$DelaySec, '/c', 'CIODIY 装机模式已完成，即将重启') -WindowStyle Hidden
}

function Invoke-DeployModeRun {
    param(
        [switch]$AutoFix,
        [switch]$RebootIfNeeded,
        [switch]$ExportReport,
        [switch]$Silent,
        [switch]$CreateRestorePoint,
        [switch]$BackupFirst,
        [switch]$RollbackOnError,
        [string]$Scenario = 'all',
        [switch]$IncludeOutdated,
        [switch]$FastMatch,
        [switch]$ForceReboot,
        [string]$AppVersion = '1.4.0',
        [scriptblock]$OnLog,
        [scriptblock]$OnProgress
    )

    if ($AutoFix) { Assert-Admin }

    $started = Get-Date
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $log = {
        param($msg)
        if (-not $Silent -and $OnLog) { & $OnLog $msg }
        elseif (-not $Silent) { Write-AppLog $msg -OnLog $null }
    }

    & $log '=== 装机模式启动 ==='
    $hw = Get-HardwareProfile -Refresh
    & $log ("设备: {0} | {1}" -f $hw.MachineTitle, $hw.PlatformLine)

    if ($OnProgress) { & $OnProgress 5 '正在扫描设备...' }
    & $log ('[{0}] 开始扫描...' -f (Get-Date -Format 'HH:mm:ss'))

    $scanResults = @(Invoke-DriverScanEngine -IncludeOutdated:$IncludeOutdated -OnLog $OnLog)
    $manifest = Get-EngineManifest
    $match = Invoke-DriverMatchEngine -ScanResults $scanResults -Manifest $manifest -OnLog $OnLog -SkipLocalIndex:$FastMatch
    $fullPlan = @($match.FixPlan)
    $fixPlan = @(Filter-FixPlanByScenario -FixPlan $fullPlan -Scenario $Scenario)
    $selected = if ($AutoFix) { @(Select-RecommendedFixPlan -FixPlan $fixPlan) } else { @() }
    $reportItems = if ($selected.Count -gt 0) { $selected } else { @(Select-RecommendedFixPlan -FixPlan $fixPlan) }

    & $log ("扫描完成: 待修复 {0} 项，推荐自动安装 {1} 项" -f $fixPlan.Count, $selected.Count)
    if ($OnProgress) { & $OnProgress 35 '扫描完成，准备安装...' }

    $installResult = $null
    $rebootNeeded = $false

    if ($AutoFix -and $selected.Count -gt 0) {
        & $log ('[{0}] 开始安装 {1} 个推荐驱动...' -f (Get-Date -Format 'HH:mm:ss'), $selected.Count)
        $installResult = Invoke-DriverFixEngine -FixPlan $selected `
            -CreateRestorePoint:$CreateRestorePoint `
            -BackupFirst:$BackupFirst `
            -RollbackOnError:$RollbackOnError `
            -OnLog $OnLog `
            -OnProgress $OnProgress
        $rebootNeeded = [bool]$installResult.RebootNeeded
        & $log ("安装结束: tx={0} status={1}" -f $installResult.TransactionId, $installResult.FinalStatus)
    } elseif ($AutoFix) {
        & $log '无推荐驱动需安装，跳过安装阶段'
    }

    if ($OnProgress) { & $OnProgress 95 '生成报告...' }

    $sw.Stop()
    $finished = Get-Date
    $status = Resolve-DeployStatus -InstallResult $installResult -SelectedCount $selected.Count -FixPlanCount $fixPlan.Count -AutoFix:$AutoFix
    if ($installResult -and $installResult.RebootNeeded) { $rebootNeeded = $true }

    $reportObj = [PSCustomObject]@{
        Status           = $status
        AppVersion       = $AppVersion
        HardwareProfile  = $hw
        ScanResults      = $scanResults
        FixPlanAll       = $fixPlan
        FixPlanSelected  = $selected
        MissingDrivers   = @(Build-DeployMissingList -FixPlan $reportItems)
        InstallLines     = @(Build-DeployInstallLines -InstallResult $installResult -FixPlan $selected)
        InstallResult    = $installResult
        RebootNeeded     = $rebootNeeded
        TransactionId    = if ($installResult) { $installResult.TransactionId } else { '' }
        Duration         = $sw.Elapsed
        StartedAt        = $started
        FinishedAt       = $finished
        ReportPath       = ''
    }

    if ($ExportReport) {
        $reportObj.ReportPath = Export-DeployHtmlReport -Report $reportObj
        & $log ("报告已导出: {0}" -f $reportObj.ReportPath)
    }

    if ($RebootIfNeeded -and $rebootNeeded) {
        & $log '需要重启，正在安排系统重启...'
        Invoke-DeployReboot -DelaySec 60 -Force:$ForceReboot
    }

    if ($OnProgress) { & $OnProgress 100 '装机模式完成' }
    & $log ('=== 装机模式完成 · {0} · 耗时 {1} ===' -f (Get-DeployStatusLabel -Status $status), (Format-DeployDuration -Span $sw.Elapsed))

    return $reportObj
}
