# Driver Engine public API (GUI / CLI / PE / remote share this layer)

param(
    [string]$AppRoot = $null
)

. (Join-Path $PSScriptRoot 'Initialize-Engine.ps1') -AppRoot $AppRoot

function Get-EngineManifest {
    $local = Get-LocalManifestPath
    if ($local) {
        return Import-DriverManifest -Path $local
    }
    return Sync-DriverManifest
}

function Invoke-DriverScanEngine {
    param(
        [switch]$IncludeOutdated,
        [scriptblock]$OnLog,
        [scriptblock]$OnProgress   # { param($pct,$msg) }
    )

    if ($OnLog) {
        & $OnLog ('[{0}] 开始扫描设备...' -f (Get-Date -Format 'HH:mm:ss'))
    } else {
        Write-AppLog 'Engine scan started'
    }

    $results = @(Invoke-DriverScan -IncludeOutdated:$IncludeOutdated -OnProgress $OnProgress)
    $results = Merge-ScanDevices -Devices $results
    $problems = @($results | Where-Object { $_.IsProblem })

    if ($OnLog) {
        & $OnLog ('[{0}] 扫描完成: {1} 个设备, {2} 个问题' -f (Get-Date -Format 'HH:mm:ss'), $results.Count, $problems.Count)
    } else {
        Write-AppLog ("Engine scan done: {0} devices, {1} problems" -f $results.Count, $problems.Count)
    }
    return $results
}

function Invoke-DriverMatchEngine {
    param(
        [Parameter(Mandatory)][array]$ScanResults,
        $Manifest = $null,
        [scriptblock]$OnLog,
        [switch]$SkipLocalIndex
    )

    if (-not $Manifest) { $Manifest = Get-EngineManifest }
    $os = Get-SystemOsProfile

    $script:UseLocalInfIndex = (-not $SkipLocalIndex) -and (Test-LocalDriverLibraryReady)
    if ($script:UseLocalInfIndex -and $OnLog) {
        & $OnLog ('[{0}] 加载本地驱动索引...' -f (Get-Date -Format 'HH:mm:ss'))
        Get-DriverInfIndex -OnLog $OnLog | Out-Null
    }

    $plan = @(Build-DriverFixPlan -ScanResults $ScanResults -Manifest $Manifest)
    $script:UseLocalInfIndex = $false

    if ($OnLog) {
        & $OnLog ('[{0}] 匹配完成: {1} 项待修复 (系统={2} build={3})' -f (Get-Date -Format 'HH:mm:ss'), $plan.Count, $os.Label, $os.Build)
    } else {
        Write-AppLog ("Engine match: {0} fix items" -f $plan.Count)
    }

    return [PSCustomObject]@{
        ScanResults = $ScanResults
        FixPlan     = $plan
        Manifest    = $Manifest
    }
}

function Invoke-DriverFixEngine {
    param(
        [Parameter(Mandatory)][array]$FixPlan,
        [switch]$CreateRestorePoint,
        [switch]$BackupFirst,
        [switch]$RollbackOnError,
        [switch]$VerifyInstall,
        [scriptblock]$OnLog,
        [scriptblock]$OnProgress
    )

    if ($BackupFirst -eq $false -and -not $PSBoundParameters.ContainsKey('BackupFirst')) {
        $BackupFirst = $true
    }
    if ($VerifyInstall -eq $false -and -not $PSBoundParameters.ContainsKey('VerifyInstall')) {
        $VerifyInstall = $true
    }

    return Invoke-FixPlan -FixPlan $FixPlan `
        -CreateRestorePoint:$CreateRestorePoint `
        -BackupFirst:$BackupFirst `
        -RollbackOnError:$RollbackOnError `
        -VerifyInstall:$VerifyInstall `
        -OnLog $OnLog `
        -OnProgress $OnProgress
}

function Invoke-DriverInstallEngine {
    param(
        [switch]$LocalLibraryOnly,
        [switch]$RollbackOnError,
        [scriptblock]$OnLog
    )

    if ($LocalLibraryOnly) {
        return Install-AllLocalDrivers -OnLog $OnLog -RollbackOnError:$RollbackOnError
    }
    throw 'Invoke-DriverInstallEngine requires -LocalLibraryOnly or pass FixPlan to Invoke-DriverFixEngine'
}

function Invoke-DriverRollbackEngine {
    param(
        [string]$TxId = '',
        [switch]$Last,
        [scriptblock]$OnLog
    )

    $tx = if ($Last -or [string]::IsNullOrWhiteSpace($TxId)) {
        Get-LatestTransaction
    } else {
        Get-DriverTransaction -TxId $TxId
    }

    if (-not $tx) { throw 'No transaction found for rollback' }
    Write-AppLog ("Engine rollback: $($tx.Id)") -OnLog $OnLog
    return Invoke-DriverTransactionRollback -Transaction $tx -OnLog $OnLog
}

function Invoke-DriverSyncEngine {
    param([scriptblock]$OnLog)
    return Sync-DriverManifest -OnLog $OnLog
}

function Invoke-AppBootstrapEngine {
    param(
        [scriptblock]$OnLog,
        [switch]$Force,
        [switch]$Background
    )
    return Invoke-AppBootstrap -OnLog $OnLog -Force:$Force -Background:$Background
}

function Invoke-DeployModeEngine {
    param(
        [switch]$AutoFix,
        [switch]$RebootIfNeeded,
        [switch]$ExportReport,
        [switch]$Silent,
        [switch]$ForceReboot,
        [switch]$CreateRestorePoint,
        [switch]$BackupFirst,
        [switch]$RollbackOnError,
        [string]$Scenario = 'all',
        [switch]$IncludeOutdated,
        [switch]$FastMatch,
        [string]$AppVersion = '1.4.0',
        [scriptblock]$OnLog,
        [scriptblock]$OnProgress
    )

    return Invoke-DeployModeRun @PSBoundParameters
}

function Invoke-DriverHealthEngine {
    param(
        [array]$ScanResults = @(),
        [array]$FixPlan = @(),
        $Manifest = $null,
        [switch]$RunScan,
        [switch]$FastMatch,
        [switch]$QuickOnly,
        [scriptblock]$OnLog
    )

    return Invoke-DriverHealthAnalysis @PSBoundParameters
}

function Invoke-DriverRepoBuildEngine {
    param(
        [string]$ReleaseTag = 'v1.1.0',
        [string]$Repo = 'yanbai9188-oss/qudong',
        [string]$ManifestVersion = '',
        [string]$OutputDir = '',
        [switch]$DryRun,
        [switch]$AddNewPackages,
        [scriptblock]$OnLog
    )

    return Invoke-BuildDriverRepository @PSBoundParameters
}

# --- v1.7.0 frozen facade: GUI/CLI must use these instead of lib internals ---

function Invoke-DriverAppScanEngine {
    param(
        [string]$Scenario = 'all',
        [switch]$IncludeOutdated,
        [switch]$FastMatch,
        [scriptblock]$OnLog,
        [scriptblock]$OnProgress,  # { param($pct,$msg) }  forwarded to UI progress bar
        $Manifest = $null
    )

    try {
        if ($OnLog) { & $OnLog ('[{0}] 正在枚举硬件设备...' -f (Get-Date -Format 'HH:mm:ss')) }
        if ($OnProgress) { try { & $OnProgress 15 '正在识别硬件...' } catch {} }
        $hw = Get-HardwareProfile
        if ($OnLog) {
            & $OnLog ('硬件画像: {0} | {1}' -f $hw.MachineTitle, $hw.PlatformLine)
        }

        $scanResults = @(Invoke-DriverScanEngine -IncludeOutdated:$IncludeOutdated -OnLog $OnLog -OnProgress $OnProgress)
        if ($OnProgress) { try { & $OnProgress 85 '正在匹配驱动包...' } catch {} }
        if (-not $Manifest) {
            try { $Manifest = Get-EngineManifest } catch { $Manifest = $null }
        }
        if ($OnLog) { & $OnLog ('[{0}] 正在匹配驱动包...' -f (Get-Date -Format 'HH:mm:ss')) }
        $match = Invoke-DriverMatchEngine -ScanResults $scanResults -Manifest $Manifest -OnLog $OnLog -SkipLocalIndex:$FastMatch
        $fullPlan = @($match.FixPlan)
        $plan = @(Invoke-DriverScenarioFilterEngine -FixPlan $fullPlan -Scenario $Scenario)

        if ($OnLog -and $Scenario -ne 'all') {
            $info = Get-DriverScenarioInfoEngine -Scenario $Scenario
            & $OnLog ("场景 [{0}]：{1} 项待修复（共 {2} 项）" -f $info.Label, $plan.Count, $fullPlan.Count)
        }

        $summary = Invoke-DriverRepairSummaryEngine -FixPlan $plan -ScanResults $scanResults -Scenario $Scenario
        $data = [PSCustomObject]@{
            ScanResults   = $scanResults
            FixPlan       = $plan
            FullFixPlan   = $fullPlan
            Scenario      = $Scenario
            Manifest      = $Manifest
            Hardware      = $hw
            RepairSummary = $summary
        }
        return New-CIODIYOperationResult -Success $true -Code 'OK' -Data $data
    } catch {
        return New-CIODIYOperationResult -Success $false -Code 'SCAN_FAILED' `
            -Message $_.Exception.Message -Detail $_.ScriptStackTrace
    }
}

function Invoke-DriverScenarioFilterEngine {
    param(
        [Parameter(Mandatory)][array]$FixPlan,
        [string]$Scenario = 'all'
    )
    return @(Filter-FixPlanByScenario -FixPlan $FixPlan -Scenario $Scenario)
}

function Get-DriverScenarioInfoEngine {
    param([string]$Scenario = 'all')
    return Get-ScenarioInfo -Scenario $Scenario
}

function Invoke-DriverRepairSummaryEngine {
    param(
        [Parameter(Mandatory)][array]$FixPlan,
        [array]$ScanResults = @(),
        [string]$Scenario = 'all',
        [array]$GridRows = @()
    )
    return Get-RepairSummary -FixPlan $FixPlan -ScanResults $ScanResults -Scenario $Scenario -GridRows $GridRows
}

function Get-DriverVisibleFixPlanEngine {
    param([Parameter(Mandatory)][array]$FixPlan)
    return @(Get-VisibleFixPlanItems -FixPlan $FixPlan)
}

function Expand-DriverFixPlanSelectionEngine {
    param(
        [Parameter(Mandatory)][array]$SelectedItems,
        [Parameter(Mandatory)][array]$FullFixPlan
    )
    return @(Expand-SelectedFixPlan -SelectedItems $SelectedItems -FullFixPlan $FullFixPlan)
}

function Get-DriverSourceStatusEngine {
    param($Manifest = $null)
    return Get-DriverSourceStatus -Manifest $Manifest
}

function Get-DriverRepositoryHealthEngine {
    try {
        $data = Get-DriverRepositoryHealth
        return New-CIODIYOperationResult -Success $true -Code 'OK' -Data $data
    } catch {
        return New-CIODIYOperationResult -Success $false -Code 'REPO_HEALTH_FAILED' `
            -Message $_.Exception.Message -Detail $_.ScriptStackTrace
    }
}

function Invoke-DriverRepositoryRepairEngine {
    param([scriptblock]$OnLog)
    try {
        $data = Repair-DriverRepository -UpdateManifestSha -DownloadMissing -OnLog $OnLog
        return New-CIODIYOperationResult -Success $true -Code 'OK' `
            -Message ([string]$data.SummaryLine) -Data $data
    } catch {
        return New-CIODIYOperationResult -Success $false -Code 'REPO_REPAIR_FAILED' `
            -Message $_.Exception.Message -Detail $_.ScriptStackTrace
    }
}

function Get-DriverLatestTransactionEngine {
    return Get-LatestTransaction
}

function Get-DriverTransactionsEngine {
    param([int]$Limit = 20)
    return @(Get-AllTransactions -Limit $Limit)
}

function Get-DriverTransactionSummaryEngine {
    param([Parameter(Mandatory)]$Transaction)
    return Get-TransactionSummaryForGui -Transaction $Transaction
}

function Test-DriverLocalLibraryReadyEngine {
    return [bool](Test-LocalDriverLibraryReady)
}

function Initialize-DriverInfIndexEngine {
    param([scriptblock]$OnLog)
    try {
        Get-DriverInfIndex -OnLog $OnLog | Out-Null
        return New-CIODIYOperationResult -Success $true -Code 'OK'
    } catch {
        return New-CIODIYOperationResult -Success $false -Code 'INF_INDEX_FAILED' `
            -Message $_.Exception.Message -Detail $_.ScriptStackTrace
    }
}

function Invoke-DriverFixEngineWrapped {
    param(
        [Parameter(Mandatory)][array]$FixPlan,
        [switch]$CreateRestorePoint,
        [switch]$BackupFirst,
        [switch]$RollbackOnError,
        [switch]$VerifyInstall,
        [scriptblock]$OnLog,
        [scriptblock]$OnProgress
    )
    try {
        $data = Invoke-DriverFixEngine @PSBoundParameters
        return New-CIODIYOperationResult -Success $true -Code 'OK' -Data $data
    } catch {
        return New-CIODIYOperationResult -Success $false -Code 'FIX_FAILED' `
            -Message $_.Exception.Message -Detail $_.ScriptStackTrace
    }
}

function Invoke-DriverRollbackEngineWrapped {
    param(
        [string]$TxId = '',
        [switch]$Last,
        [scriptblock]$OnLog
    )
    try {
        $data = Invoke-DriverRollbackEngine -TxId $TxId -Last:$Last -OnLog $OnLog
        return New-CIODIYOperationResult -Success $true -Code 'OK' -Data $data
    } catch {
        return New-CIODIYOperationResult -Success $false -Code 'ROLLBACK_FAILED' `
            -Message $_.Exception.Message -Detail $_.ScriptStackTrace
    }
}

function Get-DriverFixItemDetailsEngine {
    param([Parameter(Mandatory)]$Item, $Manifest = $null)
    return Get-DriverFixItemDetails -Item $Item -Manifest $Manifest
}

function Get-FixPlanRiskAssessmentEngine {
    param([Parameter(Mandatory)][array]$FixPlan)
    return Get-FixPlanRiskAssessment -FixPlan $FixPlan
}

function Get-DriverVersionStatusSummaryEngine {
    param([Parameter(Mandatory)][array]$FixPlan)
    return Get-DriverVersionStatusSummary -FixPlan $FixPlan
}

function Export-HardwareDriverRequestEngine {
    param([string]$OutputPath = '', [scriptblock]$OnLog)
    return Export-HardwareDriverRequest -OutputPath $OutputPath -OnLog $OnLog
}

# Public API names (do not alias over lib Invoke-DriverScan / Invoke-FixPlan)
Set-Alias -Name Invoke-DriverScanApi -Value Invoke-DriverScanEngine -Scope Script -ErrorAction SilentlyContinue
Set-Alias -Name Invoke-DriverFixApi -Value Invoke-DriverFixEngine -Scope Script -ErrorAction SilentlyContinue
Set-Alias -Name Invoke-DriverInstallApi -Value Invoke-DriverInstallEngine -Scope Script -ErrorAction SilentlyContinue
Set-Alias -Name Invoke-DriverRollbackApi -Value Invoke-DriverRollbackEngine -Scope Script -ErrorAction SilentlyContinue
