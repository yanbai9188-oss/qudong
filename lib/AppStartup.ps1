# CIODIY startup reliability layer (v1.6.10)

function Resolve-CIODIYDataRoot {
    param([string]$AppRoot = $null)
    if (Get-Command Get-AppDataRoot -ErrorAction SilentlyContinue) {
        try { return Get-AppDataRoot } catch { }
    }
    $install = if ($AppRoot) { $AppRoot } elseif ($script:AppRoot) { $script:AppRoot } else { $PSScriptRoot }
    if (-not $install) { return $null }
    try {
        $cache = Join-Path $install 'Cache'
        if (-not (Test-Path $cache)) { New-Item -ItemType Directory -Force -Path $cache -ErrorAction Stop | Out-Null }
        $test = Join-Path $cache ('._write_test_{0}' -f $PID)
        Set-Content -LiteralPath $test -Value '1' -Encoding UTF8 -ErrorAction Stop
        Remove-Item -LiteralPath $test -Force -ErrorAction SilentlyContinue
        return $install
    } catch {
        $userRoot = Get-CIODIYUserDataRoot
        if (-not (Test-Path $userRoot)) { New-Item -ItemType Directory -Force -Path $userRoot | Out-Null }
        return $userRoot
    }
}

function Write-CIODIYStartupLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$AppRoot = $null
    )
    $line = "[{0}] {1}" -f (Get-Date -Format 'o'), $Message

    # Primary path via data-root resolver
    try {
        $dataRoot = Resolve-CIODIYDataRoot -AppRoot $AppRoot
        if ($dataRoot) {
            $dir = Join-Path $dataRoot 'Logs'
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null }
            Add-Content -Path (Join-Path $dir 'startup.log') -Value $line -Encoding UTF8 -ErrorAction Stop
            return
        }
    } catch { }

    # Fallback: write directly to %LOCALAPPDATA%\Yanbai_Driver\Logs — bypasses any
    # cached data-root that might point at the old CIODIY_DriverBooster directory.
    try {
        $fallbackDir = Join-Path $env:LOCALAPPDATA 'Yanbai_Driver\Logs'
        if (-not (Test-Path $fallbackDir)) { New-Item -ItemType Directory -Force -Path $fallbackDir | Out-Null }
        Add-Content -Path (Join-Path $fallbackDir 'startup.log') -Value $line -Encoding UTF8
    } catch { }
}

function Show-CIODIYStartupFailure {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$AppRoot = $null,
        [string]$Detail = ''
    )
    Write-CIODIYStartupLog -Message ("FAIL: $Message") -AppRoot $AppRoot
    if ($Detail) { Write-CIODIYStartupLog -Message $Detail -AppRoot $AppRoot }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        if ([System.Windows.Forms.MessageBox]) {
            $body = $Message
            if ($Detail) { $body += [Environment]::NewLine + [Environment]::NewLine + $Detail }
            [void][System.Windows.Forms.MessageBox]::Show($body, 'Yanbai驱动 - 启动失败', 'OK', 'Error')
            return
        }
    } catch { }
    Write-Host $Message -ForegroundColor Red
    if ($Detail) { Write-Host $Detail -ForegroundColor DarkRed }
}

function Assert-CIODIYEngineFiles {
    param([Parameter(Mandatory)][string]$AppRoot)
    $enginePath = Join-Path $AppRoot 'engine\DriverEngine.ps1'
    $utilsPath = Join-Path $AppRoot 'lib\Utils.ps1'
    if (-not (Test-Path $enginePath)) { throw "缺少引擎文件: engine\DriverEngine.ps1" }
    if (-not (Test-Path $utilsPath)) { throw "缺少核心库: lib\Utils.ps1" }
}

function Initialize-CIODIYEngine {
    param([Parameter(Mandatory)][string]$AppRoot)
    Assert-CIODIYEngineFiles -AppRoot $AppRoot
    Write-CIODIYStartupLog -Message 'Engine files validated' -AppRoot $AppRoot
}

function Assert-CIODIYStaThread {
    $state = [System.Threading.Thread]::CurrentThread.ApartmentState
    if ($state -ne [System.Threading.ApartmentState]::STA) {
        throw "WPF 需要 STA 线程。请双击「启动驱动检测安装.bat」启动。"
    }
}

function Get-CIODIYInstanceLockPath {
    param([string]$AppRoot = $null)
    $dataRoot = Resolve-CIODIYDataRoot -AppRoot $(if ($AppRoot) { $AppRoot } else { $script:AppRoot })
    return (Join-Path $dataRoot 'Cache\app.lock')
}

function Get-CIODIYLockInfo {
    param([string]$AppRoot)
    $lockPath = Get-CIODIYInstanceLockPath -AppRoot $AppRoot
    if (-not (Test-Path $lockPath)) { return $null }
    try {
        return (Get-Content $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Stop-CIODIYOrphanLauncher {
    param(
        [string]$AppRoot,
        [int]$TargetPid = 0
    )
    if ($TargetPid -le 0 -or $TargetPid -eq $PID) { return }
    try {
        $proc = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
        if (-not $proc) { return }
        if ($proc.MainWindowHandle -eq [IntPtr]::Zero) {
            Write-CIODIYStartupLog -Message ("Stopping orphan launcher PID=$TargetPid") -AppRoot $AppRoot
            Stop-Process -Id $TargetPid -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}

function Invoke-CIODIYActivateExistingWindow {
    param([int]$ProcessId)
    try {
        $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if (-not $proc -or $proc.MainWindowHandle -eq [IntPtr]::Zero) { return $false }
        if (-not ('WinFocus' -as [type])) {
            Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;
public class WinFocus {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
        }
        [void][WinFocus]::ShowWindow($proc.MainWindowHandle, 9)
        return [bool][WinFocus]::SetForegroundWindow($proc.MainWindowHandle)
    } catch {
        return $false
    }
}

function Clear-CIODIYStaleInstanceLock {
    param([string]$AppRoot = $null)
    $root = if ($AppRoot) { $AppRoot } else { $script:AppRoot }
    $lockPath = Get-CIODIYInstanceLockPath -AppRoot $root
    if (-not (Test-Path $lockPath)) { return }

    $lock = Get-CIODIYLockInfo -AppRoot $root
    if (-not $lock -or -not $lock.pid) {
        Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
        Write-CIODIYStartupLog -Message 'Removed invalid app.lock' -AppRoot $root
        return
    }

    $oldPid = [int]$lock.pid
    if ($oldPid -eq $PID) { return }

    $proc = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
    if (-not $proc) {
        Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
        Write-CIODIYStartupLog -Message "Cleared stale lock (dead PID=$oldPid)" -AppRoot $root
        return
    }

    if (Invoke-CIODIYActivateExistingWindow -ProcessId $oldPid) {
        Write-CIODIYStartupLog -Message "Activated existing window PID=$oldPid" -AppRoot $root
        return
    }

    $ageSec = 9999
    if ($lock.started) {
        try {
            $started = [DateTime]::Parse([string]$lock.started)
            $ageSec = ((Get-Date) - $started).TotalSeconds
        } catch { }
    }

    # A powershell/pwsh process with no main window is a half-started or stuck launcher.
    # Clean it up regardless of age — it will never show a window on its own.
    $isOrphanLauncher = ($proc.MainWindowHandle -eq [IntPtr]::Zero) -and
                        ($proc.ProcessName -in @('powershell', 'pwsh'))

    if ($ageSec -gt 15 -or $isOrphanLauncher) {
        Write-CIODIYStartupLog -Message ("Orphan launcher PID=$oldPid age=${ageSec}s name=$($proc.ProcessName), stopping") -AppRoot $root
        Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
        Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
    } else {
        # Young process, not a headless PS launcher — could be a real app still loading.
        # Leave the lock in place; the new instance will block.
        Write-CIODIYStartupLog -Message ("Young process PID=$oldPid age=${ageSec}s, not cleaning lock") -AppRoot $root
    }
}

function Test-CIODIYSingleInstance {
    param([string]$AppRoot = $null)

    $root = if ($AppRoot) { $AppRoot } else { $script:AppRoot }
    Clear-CIODIYStaleInstanceLock -AppRoot $root

    $dataRoot = Resolve-CIODIYDataRoot -AppRoot $root
    $cacheDir = Join-Path $dataRoot 'Cache'
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    }

    $lockPath = Get-CIODIYInstanceLockPath -AppRoot $root
    $lock = Get-CIODIYLockInfo -AppRoot $root
    if ($lock -and $lock.pid) {
        $oldPid = [int]$lock.pid
        if ($oldPid -gt 0 -and $oldPid -ne $PID) {
            $proc = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
            if ($proc) {
                # Real visible window → bring it to front and exit.
                if (Invoke-CIODIYActivateExistingWindow -ProcessId $oldPid) {
                    Write-CIODIYStartupLog -Message "Second launch -> focus PID=$oldPid" -AppRoot $root
                    return $false
                }

                # Process exists but has no visible window.
                # If it is a headless powershell/pwsh it is a stuck launcher — clean up and continue.
                $isOrphan = ($proc.MainWindowHandle -eq [IntPtr]::Zero) -and
                            ($proc.ProcessName -in @('powershell', 'pwsh'))
                if ($isOrphan) {
                    Write-CIODIYStartupLog -Message "Cleaning orphan PID=$oldPid ($($proc.ProcessName)), starting fresh" -AppRoot $root
                    Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
                    Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
                    # Fall through to write new lock below
                } else {
                    # Non-PS process with recycled PID, or a real app without a window yet.
                    Stop-CIODIYOrphanLauncher -AppRoot $root -TargetPid $oldPid
                    Write-CIODIYStartupLog -Message "Blocked duplicate PID=$oldPid" -AppRoot $root
                    return $false
                }
            } else {
                Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
            }
        } else {
            Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
        }
    }

    (@{
        pid     = $PID
        started = (Get-Date -Format 'o')
        version = if ($script:AppVersion) { $script:AppVersion } else { '' }
    } | ConvertTo-Json) | Set-Content $lockPath -Encoding UTF8
    $script:CIODIYInstanceLockPath = $lockPath
    Write-CIODIYStartupLog -Message "Instance lock PID=$PID" -AppRoot $root
    return $true
}

function Remove-CIODIYInstanceLock {
    $path = if ($script:CIODIYInstanceLockPath) { $script:CIODIYInstanceLockPath } else { Get-CIODIYInstanceLockPath }
    if ($path -and (Test-Path $path)) {
        Remove-Item $path -Force -ErrorAction SilentlyContinue
    }
}

function Test-CIODIYRequiredControls {
    param(
        [Parameter(Mandatory)][hashtable]$Controls,
        [string[]]$Required
    )
    $missing = New-Object System.Collections.ArrayList
    foreach ($name in $Required) {
        if (-not $Controls.ContainsKey($name) -or -not $Controls[$name]) {
            [void]$missing.Add($name)
        }
    }
    if ($missing.Count -gt 0) {
        throw ('界面控件缺失: {0}' -f ($missing -join ', '))
    }
}

function ConvertTo-CIODIYBrush {
    param([string]$Color)
    if ([string]::IsNullOrWhiteSpace($Color)) { return $null }
    $obj = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
    return $obj -as [System.Windows.Media.Brush]
}

# 写入结构化会话摘要行，方便日志检索与批量脚本解析
function Write-CIODIYSessionSummary {
    param(
        [Parameter(Mandatory)][string]$Operation,   # 'SCAN' | 'FIX' | 'DEPLOY'
        [int]$OK      = 0,
        [int]$Fail    = 0,
        [int]$Total   = 0,
        [bool]$Reboot = $false,
        [string]$Status = '',
        [string]$AppRoot = $null
    )
    $dataRoot = Resolve-CIODIYDataRoot -AppRoot $AppRoot
    if (-not $dataRoot) { return }
    try {
        $dir = Join-Path $dataRoot 'Logs'
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $path = Join-Path $dir 'session.log'
        $sep  = '=' * 60
        $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $rebootStr = if ($Reboot) { 'YES' } else { 'NO' }
        $statusStr = if ($Status) { " status=$Status" } else { '' }
        $line = "[SUMMARY] $ts op=$Operation total=$Total ok=$OK fail=$Fail reboot=$rebootStr$statusStr"
        Add-Content -Path $path -Value $sep -Encoding UTF8
        Add-Content -Path $path -Value $line -Encoding UTF8
        Add-Content -Path $path -Value $sep -Encoding UTF8
    } catch { }
}
