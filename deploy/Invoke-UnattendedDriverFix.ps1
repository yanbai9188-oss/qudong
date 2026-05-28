#requires -Version 5.1
# Unattended driver fix for intranet / batch deployment
param(
    [ValidateSet('all', 'audio', 'network', 'usb')]
    [string]$Scenario = 'all',
    [switch]$LocalOnly,
    [switch]$SkipRestore,
    [switch]$NoRollback,
    [string]$LogDir = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$AppRoot = Split-Path $PSScriptRoot -Parent
$scriptPath = Join-Path $AppRoot 'DriverBooster.ps1'

if ($Help) {
    @"
CIODIY 内网无人值守驱动修复
用法:
  .\deploy\Invoke-UnattendedDriverFix.ps1 [-Scenario all|audio|network|usb]
      [-LocalOnly] [-SkipRestore] [-NoRollback] [-LogDir path]

退出码: 0=成功  1=失败/回滚  2=成功需重启
"@
    exit 0
}

if (-not $LogDir) { $LogDir = Join-Path $AppRoot 'Logs' }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile = Join-Path $LogDir "unattended_$stamp.log"

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Host $line
}

Write-Log ("=" * 60)
Write-Log "=== Yanbai驱动无人值守修复 ==="
Write-Log ("=" * 60)
Write-Log "Scenario=$Scenario LocalOnly=$LocalOnly AppRoot=$AppRoot"
Write-Log "Host=$env:COMPUTERNAME User=$env:USERNAME"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log 'ERROR: Administrator required'
    exit 1
}

. (Join-Path $AppRoot 'engine\DriverEngine.ps1') -AppRoot $AppRoot

$onLog = { param($m) Write-Log $m }

try {
    if (-not $LocalOnly) {
        Write-Log 'Syncing manifest...'
        $null = Invoke-DriverSyncEngine -OnLog $onLog
    } else {
        Write-Log 'LocalOnly: skip manifest sync'
    }

    Write-Log 'Scanning...'
    $scan = @(Invoke-DriverScanEngine -OnLog $onLog)
    $manifest = Get-EngineManifest
    $match = Invoke-DriverMatchEngine -ScanResults $scan -Manifest $manifest -OnLog $onLog
    $fullPlan = @($match.FixPlan)
    $plan = if ($Scenario -ne 'all') {
        @(Filter-FixPlanByScenario -FixPlan $fullPlan -Scenario $Scenario)
    } else {
        $fullPlan
    }

    Write-Log ("Fix plan: {0} item(s) (scenario={1}, total={2})" -f $plan.Count, $Scenario, $fullPlan.Count)

    if ($LocalOnly) {
        foreach ($item in @($plan)) {
            if ($item.Action -ne 'InstallLocal') {
                $item.Action = 'InstallLocal'
            }
        }
        $plan = @($plan | Where-Object { $_.Package -or $_.Action -eq 'InstallLocal' })
    }

    if ($plan.Count -eq 0) {
        Write-Log 'No fix items; exit 0'
        exit 0
    }

    Write-Log 'Installing...'
    $result = Invoke-DriverFixEngine -FixPlan $plan `
        -CreateRestorePoint:(-not $SkipRestore) `
        -BackupFirst:(-not $SkipRestore) `
        -RollbackOnError:(-not $NoRollback) `
        -OnLog $onLog

    $allResults = @($result.Results)
    $ok   = @($allResults | Where-Object { $_.Success }).Count
    $fail = @($allResults | Where-Object { -not $_.Success }).Count
    Write-Log ("完成: tx={0} status={1} ok={2} fail={3} reboot={4}" -f `
        $result.TransactionId, $result.FinalStatus, $ok, $fail, $result.RebootNeeded)

    # 输出结构化摘要行（供批量脚本解析，格式固定勿改）
    $summaryLine = ("SUMMARY host={0} status={1} ok={2} fail={3} reboot={4} tx={5} logfile={6}" -f `
        $env:COMPUTERNAME, $result.FinalStatus, $ok, $fail, ([int][bool]$result.RebootNeeded),
        $result.TransactionId, $logFile)
    Write-Host $summaryLine
    Add-Content -Path $logFile -Value $summaryLine -Encoding UTF8

    # 写入 JSON 摘要文件，方便批量工具读取
    $summaryJson = [PSCustomObject]@{
        host       = $env:COMPUTERNAME
        timestamp  = (Get-Date -Format 'o')
        status     = $result.FinalStatus
        ok         = $ok
        fail       = $fail
        reboot     = [bool]$result.RebootNeeded
        tx         = $result.TransactionId
        logfile    = $logFile
        drivers    = @($result.Results | ForEach-Object {
            [PSCustomObject]@{
                device  = $_.Device
                success = $_.Success
                pkg     = $_.PackageId
                error   = if ($_.Error) { [string]$_.Error } else { $null }
            }
        })
    }
    $jsonPath = Join-Path $LogDir ("unattended_${stamp}_result.json")
    ($summaryJson | ConvertTo-Json -Depth 5) | Set-Content $jsonPath -Encoding UTF8
    Write-Log ("结果 JSON：{0}" -f $jsonPath)

    # 写结构化会话摘要
    if (Get-Command Write-CIODIYSessionSummary -ErrorAction SilentlyContinue) {
        Write-CIODIYSessionSummary -Operation 'FIX' -OK $ok -Fail $fail `
            -Total ([int]$allResults.Count) -Reboot ([bool]$result.RebootNeeded) `
            -Status $result.FinalStatus -AppRoot $AppRoot
    }

    if ($result.FinalStatus -eq 'committed') {
        exit $(if ($result.RebootNeeded) { 2 } else { 0 })
    }
    exit 1
} catch {
    Write-Log ("FATAL: {0}" -f $_.Exception.Message)
    Write-Log ("堆栈: {0}" -f $_.ScriptStackTrace)
    $summaryLine = ("SUMMARY host={0} status=fatal ok=0 fail=0 reboot=0 tx= logfile={1}" -f $env:COMPUTERNAME, $logFile)
    Write-Host $summaryLine
    exit 1
}
