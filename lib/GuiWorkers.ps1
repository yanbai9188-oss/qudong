# GUI background workers and dispatcher helpers (v1.8.7) - PS Runspace based
# BackgroundWorker doesn't carry PowerShell session state into worker thread,
# so commands like Invoke-AppScan are unresolvable. We use a real PS Runspace
# that loads the full engine + GUI controllers, with auto closure capture
# from the caller scope.

function Write-CIODIYGuiLog {
    param([string]$Message)
    $ctx = Get-CIODIYGuiContext
    $txtLog = Get-CIODIYGuiControl -Name 'TxtLog'
    $window = $ctx.Window
    if (-not $txtLog -or -not $window) { return }

    $line = [string]$Message
    if ($window.Dispatcher.CheckAccess()) {
        if ($txtLog.Text.Length -lt 8) { $txtLog.Text = $line }
        else { $txtLog.Text += [Environment]::NewLine + $line }
        try { $txtLog.ScrollToEnd() } catch {}
    } else {
        $captured_line = $line
        [void]$window.Dispatcher.BeginInvoke([System.Action]({
            Write-CIODIYGuiLog -Message $captured_line
        }.GetNewClosure()))
    }
}

function Show-CIODIYToast {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info','Success','Warning','Error')]
        [string]$Level = 'Info',
        [int]$DurationMs = 4000
    )

    $ctx = Get-CIODIYGuiContext
    if (-not $ctx -or -not $ctx.Window) { return }
    # NOTE: do not name a local var "$host" - PowerShell's built-in $Host
    # variable is read-only and any assignment errors at parse time.
    $toastHost = Get-CIODIYGuiControl -Name 'ToastHost'
    if (-not $toastHost) { return }

    $window = $ctx.Window
    $action = {
        $accent = switch ($Level) {
            'Success' { '#22C55E' }
            'Warning' { '#F59E0B' }
            'Error'   { '#EF4444' }
            default   { '#3B82F6' }
        }
        $icon = switch ($Level) {
            'Success' { 'OK' }
            'Warning' { '!' }
            'Error'   { 'X' }
            default   { 'i' }
        }

        $border = New-Object System.Windows.Controls.Border
        $border.Background = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString('#1E2430'))
        $border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString($accent))
        $border.BorderThickness = New-Object System.Windows.Thickness 1
        $border.CornerRadius = New-Object System.Windows.CornerRadius 8
        $border.Padding = New-Object System.Windows.Thickness 14, 10, 14, 10
        $border.Margin = New-Object System.Windows.Thickness 0, 6, 0, 0
        $border.MinWidth = 280
        $border.MaxWidth = 420
        $border.Opacity = 0
        $eff = New-Object System.Windows.Media.Effects.DropShadowEffect
        $eff.BlurRadius = 16; $eff.ShadowDepth = 0; $eff.Opacity = 0.45
        $eff.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('Black')
        $border.Effect = $eff

        $stack = New-Object System.Windows.Controls.StackPanel
        $stack.Orientation = 'Horizontal'

        $iconBlock = New-Object System.Windows.Controls.TextBlock
        $iconBlock.Text = $icon
        $iconBlock.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString($accent))
        $iconBlock.FontWeight = 'Bold'
        $iconBlock.FontSize = 13
        $iconBlock.VerticalAlignment = 'Center'
        $iconBlock.Margin = New-Object System.Windows.Thickness 0, 0, 10, 0
        $iconBlock.MinWidth = 18
        $iconBlock.TextAlignment = 'Center'

        $textBlock = New-Object System.Windows.Controls.TextBlock
        $textBlock.Text = $Message
        $textBlock.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString('#F1F5F9'))
        $textBlock.FontSize = 12
        $textBlock.TextWrapping = 'Wrap'
        $textBlock.VerticalAlignment = 'Center'

        [void]$stack.Children.Add($iconBlock)
        [void]$stack.Children.Add($textBlock)
        $border.Child = $stack

        [void]$toastHost.Items.Add($border)

        # Fade in
        $fadeIn = New-Object System.Windows.Media.Animation.DoubleAnimation 0, 1, ([TimeSpan]::FromMilliseconds(220))
        $border.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)

        # Schedule fade out + remove
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds($DurationMs)
        $timer.Add_Tick({
            $timer.Stop()
            $fadeOut = New-Object System.Windows.Media.Animation.DoubleAnimation 1, 0, ([TimeSpan]::FromMilliseconds(280))
            $fadeOut.Add_Completed({
                try { [void]$toastHost.Items.Remove($border) } catch {}
            })
            $border.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeOut)
        }.GetNewClosure())
        $timer.Start()
    }.GetNewClosure()

    if ($window.Dispatcher.CheckAccess()) {
        & $action
    } else {
        [void]$window.Dispatcher.BeginInvoke([System.Action]$action)
    }
}

function Set-CIODIYGuiProgress {
    param([double]$Value, [string]$Text = $null)
    $ctx = Get-CIODIYGuiContext
    if (-not $ctx) { return }
    $progress = Get-CIODIYGuiControl -Name 'Progress'
    $txtProgress = Get-CIODIYGuiControl -Name 'TxtProgress'
    $txtPercent = Get-CIODIYGuiControl -Name 'TxtProgressPercent'

    $apply = {
        if ($progress) {
            # Switch off indeterminate mode as soon as we have a real percentage
            if ($progress.IsIndeterminate) { $progress.IsIndeterminate = $false }
            $current = [double]$progress.Value
            $target = [Math]::Max(0, [Math]::Min(100, [double]$Value))
            if ([Math]::Abs($current - $target) -lt 0.5) {
                $progress.Value = $target
            } else {
                $anim = New-Object System.Windows.Media.Animation.DoubleAnimation $target, ([TimeSpan]::FromMilliseconds(380))
                $anim.EasingFunction = New-Object System.Windows.Media.Animation.QuadraticEase
                $progress.BeginAnimation([System.Windows.Controls.ProgressBar]::ValueProperty, $anim)
            }
            if ($txtPercent) {
                $txtPercent.Text = if ($target -gt 0 -and $target -lt 100) { ('{0}%' -f [int]$target) } else { '' }
            }
        }
        if ($txtProgress -and $Text) { $txtProgress.Text = $Text }
    }.GetNewClosure()

    if ($ctx.Window.Dispatcher.CheckAccess()) { & $apply }
    else { [void]$ctx.Window.Dispatcher.BeginInvoke([System.Action]$apply) }
}

function Initialize-CIODIYGuiLogCallback {
    $ctx = Get-CIODIYGuiContext
    $window = $ctx.Window
    $progress = Get-CIODIYGuiControl -Name 'Progress'
    $txtProgress = Get-CIODIYGuiControl -Name 'TxtProgress'
    $txtPercent = Get-CIODIYGuiControl -Name 'TxtProgressPercent'

    $ctx.LogCallback = {
        param($msg)
        $msgStr = [string]$msg
        Write-CIODIYGuiLog -Message $msgStr
        if ($ctx.State.IsBusy -and $progress) {
            # Capture current values so the async BeginInvoke action sees the right snapshot.
            # Without GetNewClosure(), [System.Action]{} resolves variables on the UI thread
            # at dispatch time, not at the time of enqueueing — causing stale/null references.
            $captured_msgStr     = $msgStr
            $captured_progress   = $progress
            $captured_txtProgress = $txtProgress
            $captured_txtPercent  = $txtPercent
            $captured_window      = $window
            [void]$window.Dispatcher.BeginInvoke([System.Action]({
                $val = [double]$captured_progress.Value
                $cleanMsg = $captured_msgStr -replace '^\[\d{2}:\d{2}:\d{2}\]\s*', ''

                $sub = $null
                try { $sub = $captured_window.FindName('TxtSubtitle') } catch {}
                if ($sub) {
                    if ($cleanMsg -match '正在枚举硬件') {
                        $sub.Text = '正在枚举硬件设备...'
                    } elseif ($cleanMsg -match '硬件画像[:：](.+)') {
                        $sub.Text = '检测到: ' + $matches[1].Trim()
                    } elseif ($cleanMsg -match '正在匹配驱动') {
                        $sub.Text = '正在匹配驱动包...'
                    } elseif ($cleanMsg -match '匹配完成[:：].+(\d+)\s*项') {
                        $sub.Text = '匹配完成，待修复 ' + $matches[1] + ' 项'
                    } elseif ($cleanMsg -match '扫描完成[:：].+?(\d+)\s*个设备') {
                        $sub.Text = '扫描完成，共 ' + $matches[1] + ' 个设备'
                    } elseif ($cleanMsg -match '下载[:：]\s*(.+)\s*\.\.\.') {
                        $sub.Text = '下载中: ' + $matches[1].Trim()
                    } elseif ($cleanMsg -match 'SHA256\s*校验通过') {
                        $sub.Text = '校验通过，正在解压...'
                    } elseif ($cleanMsg -match 'pnputil.*install|安装 INF') {
                        $sub.Text = '正在安装驱动 (pnputil)...'
                    }
                }

                $newValue = $val
                if ($captured_msgStr -match '扫描完成|Scan complete') {
                    $newValue = 62
                } elseif ($captured_msgStr -match '匹配完成|Match complete') {
                    $newValue = 92
                } elseif ($captured_msgStr -match '正在匹配|matching|Matching|enumerat|Enumerat') {
                    if ($val -lt 55) { $newValue = 55 }
                } elseif ($val -lt 28) {
                    $newValue = 28
                } elseif ($val -lt 90) {
                    $newValue = [Math]::Min(90, $val + 1.5)
                }

                if ([Math]::Abs($newValue - $val) -ge 0.5) {
                    $target = [Math]::Max(0, [Math]::Min(100, [double]$newValue))
                    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation $target, ([TimeSpan]::FromMilliseconds(380))
                    $anim.EasingFunction = New-Object System.Windows.Media.Animation.QuadraticEase
                    $captured_progress.BeginAnimation([System.Windows.Controls.ProgressBar]::ValueProperty, $anim)
                    if ($captured_txtPercent) {
                        $captured_txtPercent.Text = if ($target -gt 0 -and $target -lt 100) { ('{0}%' -f [int]$target) } else { '' }
                    }
                }
            }.GetNewClosure()))
        }
    }
}

function Invoke-CIODIYGuiThread {
    param([scriptblock]$Action)
    $ctx = Get-CIODIYGuiContext
    $window = $ctx.Window
    if ($window.Dispatcher.CheckAccess()) {
        & $Action
    } else {
        [void]$window.Dispatcher.Invoke([System.Action]$Action)
    }
}

function Set-CIODIYGuiBusyState {
    param([bool]$Busy, [string]$ProgressText = '')
    $ctx = Get-CIODIYGuiContext
    $ctx.State.IsBusy = $Busy

    $toggleNames = @(
        'BtnScan','BtnFixAll','BtnFixRecommended','BtnQuickFix','BtnSync','BtnInstallLocal',
        'BtnScenarioAudio','BtnScenarioNetwork','BtnScenarioUsb','BtnScenarioAll',
        'BtnRepoRepair','BtnRollbackLast','BtnRollbackSelected','BtnSelectAll',
        'BtnSelectNone','BtnSelectRecommended','BtnDeployStart'
    )
    foreach ($n in $toggleNames) {
        $btn = Get-CIODIYGuiControl -Name $n
        if ($btn) { $btn.IsEnabled = -not $Busy }
    }

    $txtProgress = Get-CIODIYGuiControl -Name 'TxtProgress'
    $txtPercent  = Get-CIODIYGuiControl -Name 'TxtProgressPercent'
    $progress    = Get-CIODIYGuiControl -Name 'Progress'
    $statusDot   = Get-CIODIYGuiControl -Name 'StatusDot'

    # ── Text update (must happen before anything that can throw) ─────────────
    if ($txtProgress -and $ProgressText) { $txtProgress.Text = $ProgressText }
    elseif (-not $Busy -and $txtProgress -and -not $ProgressText) { $txtProgress.Text = '准备就绪' }

    # ── Progress bar reset ────────────────────────────────────────────────────
    try {
        if (-not $Busy) {
            if ($txtPercent) { $txtPercent.Text = '' }
            if ($progress) {
                $progress.IsIndeterminate = $false
                $progress.BeginAnimation([System.Windows.Controls.ProgressBar]::ValueProperty, $null)
                $progress.Value = 0
            }
        } else {
            if ($progress) {
                $progress.BeginAnimation([System.Windows.Controls.ProgressBar]::ValueProperty, $null)
                $progress.Value = 0
                $progress.IsIndeterminate = $true
            }
            if ($txtPercent) { $txtPercent.Text = '' }
        }
    } catch {}

    # ── Status dot: orange when busy, green when idle ─────────────────────────
    # Use BrushConverter (instance method) — ColorConverter::ConvertFromString is
    # NOT static and would throw if called with :: notation.
    if ($statusDot) {
        try {
            $dotColor = if ($Busy) { '#FF8533' } else { '#22C55E' }
            $statusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($dotColor)
        } catch {}
    }
}

# Reusable runspace pool to avoid expensive engine reload on every worker
$script:CIODIYWorkerRunspacePool = $null

function Get-CIODIYWorkerRunspace {
    param([Parameter(Mandatory)][string]$AppRoot)

    if ($script:CIODIYWorkerRunspacePool -and $script:CIODIYWorkerRunspacePool.RunspaceStateInfo.State -eq 'Opened') {
        return $script:CIODIYWorkerRunspacePool
    }

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.ApartmentState = [System.Threading.ApartmentState]::STA
    $iss.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $rs = [runspacefactory]::CreateRunspace($iss)
    $rs.Open()

    # Bootstrap engine in this runspace once. DriverEngine.ps1 internally loads
    # Initialize-Engine.ps1 plus the public engine API surface (Invoke-DriverAppScanEngine,
    # Invoke-DriverFixEngine, Invoke-DriverHealthEngine, etc.).
    $rs.SessionStateProxy.SetVariable('__CIODIYAppRoot', $AppRoot)
    $bootstrap = [powershell]::Create()
    $bootstrap.Runspace = $rs
    [void]$bootstrap.AddScript({
        $ErrorActionPreference = 'Continue'
        $script:AppRoot = $__CIODIYAppRoot
        $global:DriverBoosterAppRoot = $__CIODIYAppRoot
        . (Join-Path $__CIODIYAppRoot 'engine\DriverEngine.ps1') -AppRoot $__CIODIYAppRoot
        . (Join-Path $__CIODIYAppRoot 'lib\AppController.ps1')
        # Load job-queue helpers so DoWork scriptblocks can submit / poll service jobs
        $jqPath = Join-Path $__CIODIYAppRoot 'lib\JobQueue.ps1'
        if (Test-Path $jqPath) { . $jqPath }
        # Ensure ScheduledTasks module is available so Test-CIODIYServiceWorkerAvailable
        # (which calls Get-ScheduledTask) works inside the worker runspace
        Import-Module ScheduledTasks -ErrorAction SilentlyContinue
        $null = New-AppSessionState
        try { Import-AppManifest } catch { Write-Host "Manifest load skipped: $($_.Exception.Message)" }
    })
    [void]$bootstrap.Invoke()
    # Surface any engine-load errors so they don't silently make the runspace unusable
    if ($bootstrap.HadErrors) {
        $errMsgs = ($bootstrap.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '
        Write-CIODIYStartupLog -Message "Worker runspace bootstrap errors: $errMsgs" -AppRoot $AppRoot
    }
    $bootstrap.Dispose()

    $script:CIODIYWorkerRunspacePool = $rs
    return $rs
}

function Get-CIODIYWorkerClosureVariables {
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock)

    $reserved = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@(
            'true','false','null','_','PSItem','PSCmdlet','args','this','input',
            'MyInvocation','PWD','OFS','PSScriptRoot','PSCommandPath','PSBoundParameters',
            'ErrorActionPreference','VerbosePreference','DebugPreference',
            'WarningPreference','ProgressPreference','InformationPreference',
            'ConfirmPreference','WhatIfPreference','HOME','HOST','PID',
            'matches','LASTEXITCODE','Error','ExecutionContext','StackTrace'
        ),
        [System.StringComparer]::OrdinalIgnoreCase
    )

    $captured = @{}
    try {
        $varNodes = $ScriptBlock.Ast.FindAll({
            param($a) $a -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true)

        foreach ($node in $varNodes) {
            $name = $node.VariablePath.UserPath
            if (-not $name) { continue }
            if ($reserved.Contains($name)) { continue }
            if ($captured.ContainsKey($name)) { continue }

            $val = $null
            $found = $false
            for ($scope = 1; $scope -le 6 -and -not $found; $scope++) {
                try {
                    $v = Get-Variable -Name $name -Scope $scope -ErrorAction Stop
                    $val = $v.Value
                    $found = $true
                } catch {}
            }
            if ($found) {
                $captured[$name] = $val
            }
        }
    } catch {
        Write-CIODIYStartupLog -Message ("Closure capture failed: {0}" -f $_.Exception.Message) -AppRoot $script:AppRoot
    }
    return $captured
}

function Start-CIODIYGuiWorker {
    param(
        [Parameter(Mandatory)][scriptblock]$DoWork,
        [scriptblock]$OnComplete,
        [scriptblock]$OnError,
        [switch]$Force   # Skip IsBusy check (for internal use only)
    )

    $ctx = Get-CIODIYGuiContext

    # Prevent concurrent workers — a second worker on the same shared runspace would
    # corrupt session state and cause unpredictable failures.
    if (-not $Force -and $ctx.State['IsBusy']) {
        Write-CIODIYGuiLog 'Worker busy — ignoring duplicate start request'
        return
    }

    $window = $ctx.Window
    $appRoot = if ($global:DriverBoosterAppRoot) {
        $global:DriverBoosterAppRoot
    } elseif ($script:AppRoot) {
        $script:AppRoot
    } else {
        Split-Path $PSCommandPath -Parent | Split-Path -Parent
    }

    Write-CIODIYStartupLog -Message 'Worker: Start-CIODIYGuiWorker entered' -AppRoot $appRoot

    # Auto-capture closure variables from caller scope
    $vars = Get-CIODIYWorkerClosureVariables -ScriptBlock $DoWork
    Write-CIODIYStartupLog -Message ("Worker: captured {0} closure vars" -f $vars.Count) -AppRoot $appRoot

    # Build a worker-side $ctx that mirrors UI ctx but uses a thread-safe log queue.
    # Worker-side $ctx must be a NEW hashtable so DoWork closures see worker LogCallback.
    $logQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $workerCtx = @{
        State = $ctx.State    # state hashtable is shared (just for read access; mutation should happen on UI thread)
        Window = $ctx.Window  # WPF Window: Dispatcher is thread-safe to access
        AppVersion = $ctx.AppVersion
    }

    # Acquire / open the long-lived runspace (engine already loaded).
    Write-CIODIYStartupLog -Message 'Worker: acquiring runspace' -AppRoot $appRoot
    $rs = Get-CIODIYWorkerRunspace -AppRoot $appRoot
    Write-CIODIYStartupLog -Message 'Worker: runspace ready' -AppRoot $appRoot

    # Inject variables AND a worker-side $ctx with queue-based LogCallback.
    foreach ($k in $vars.Keys) {
        try { $rs.SessionStateProxy.SetVariable($k, $vars[$k]) } catch {}
    }
    $rs.SessionStateProxy.SetVariable('__CIODIYWorkerCtx', $workerCtx)
    $rs.SessionStateProxy.SetVariable('__CIODIYLogQueue', $logQueue)
    $rs.SessionStateProxy.SetVariable('__CIODIYDoWorkSrc', $DoWork.ToString())

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        $ErrorActionPreference = 'Continue'

        try {
            [void]$__CIODIYLogQueue.Enqueue('[worker] entered runspace script')
        } catch {}

        # Build worker $ctx with queue-pushing log callback. Override any caller-injected
        # $ctx that captured the UI runspace dispatcher (which would be unusable here).
        $localQ = $__CIODIYLogQueue
        $ctx = $__CIODIYWorkerCtx
        $ctx.LogCallback = {
            param($m)
            try { [void]$localQ.Enqueue([string]$m) } catch {}
        }.GetNewClosure()

        try {
            $sb = [scriptblock]::Create($__CIODIYDoWorkSrc)
            [void]$localQ.Enqueue('[worker] DoWork compiled, invoking')
            $result = & $sb
            [void]$localQ.Enqueue("[worker] DoWork returned, type=$(if ($null -ne $result) { $result.GetType().Name } else { 'null' })")
            return $result
        } catch {
            $msg = ("[worker][error] {0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace)
            [void]$localQ.Enqueue($msg)
            throw
        }
    })

    Write-CIODIYStartupLog -Message 'Worker: calling BeginInvoke' -AppRoot $appRoot
    $async = $ps.BeginInvoke()
    Write-CIODIYStartupLog -Message 'Worker: BeginInvoke returned, starting drain timer' -AppRoot $appRoot

    # Drain queue + check completion via DispatcherTimer on UI thread.
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $finished = [ref]$false

    $tickHandler = {
        # Drain log queue
        $msg = $null
        $count = 0
        while ($count -lt 80 -and $logQueue.TryDequeue([ref]$msg)) {
            try {
                if ($ctx.LogCallback) { & $ctx.LogCallback $msg }
                else { Write-CIODIYGuiLog -Message $msg }
            } catch {}
            $count++
        }

        if ($async.IsCompleted -and -not $finished.Value) {
            $finished.Value = $true
            $timer.Stop()

            try {
                Write-CIODIYStartupLog -Message 'Worker: async completed, calling EndInvoke' -AppRoot $script:AppRoot
                $output = $ps.EndInvoke($async)
                Write-CIODIYStartupLog -Message ("Worker: EndInvoke returned {0} items, HadErrors={1}" -f @($output).Count, $ps.HadErrors) -AppRoot $script:AppRoot

                # Drain any remaining log lines after completion
                $remaining = $null
                while ($logQueue.TryDequeue([ref]$remaining)) {
                    try {
                        if ($ctx.LogCallback) { & $ctx.LogCallback $remaining }
                        else { Write-CIODIYGuiLog -Message $remaining }
                    } catch {}
                }

                # Surface any errors collected on the error stream
                $errLines = @()
                if ($ps.HadErrors -and $ps.Streams.Error -and $ps.Streams.Error.Count -gt 0) {
                    foreach ($er in $ps.Streams.Error) { $errLines += $er.ToString() }
                }

                $result = $null
                if ($output -and $output.Count -gt 0) {
                    $result = $output[$output.Count - 1]
                }

                if ($errLines.Count -gt 0 -and -not $result) {
                    $errMsg = ($errLines -join "`n")
                    if ($OnError) { & $OnError $errMsg }
                    else {
                        Write-CIODIYGuiLog -Message ("Worker error: {0}" -f $errMsg)
                        Set-CIODIYGuiBusyState -Busy $false -ProgressText '就绪'
                    }
                    return
                }

                # Log non-fatal errors but still call OnComplete
                foreach ($el in $errLines) {
                    Write-CIODIYGuiLog -Message ("(warn) {0}" -f $el)
                }

                if ($OnComplete) {
                    try { & $OnComplete $result }
                    catch {
                        $cbMsg = "Callback failed: {0}`n  At: {1}" -f $_.Exception.Message, $_.InvocationInfo.PositionMessage
                        Write-CIODIYGuiLog -Message $cbMsg
                        try { Write-CIODIYStartupLog -Message $cbMsg -AppRoot $script:AppRoot } catch {}
                        Set-CIODIYGuiBusyState -Busy $false -ProgressText '就绪'
                    }
                }
            } catch {
                $em = $_.Exception.Message
                if ($OnError) {
                    try { & $OnError $em } catch {
                        Write-CIODIYGuiLog -Message ("OnError failed: {0}" -f $_.Exception.Message)
                    }
                } else {
                    Write-CIODIYGuiLog -Message ("Worker invoke failed: {0}" -f $em)
                    Set-CIODIYGuiBusyState -Busy $false -ProgressText '就绪'
                }
            } finally {
                try { $ps.Dispose() } catch {}
                # Do NOT close the shared runspace here: it is reused.
            }
        }
    }.GetNewClosure()

    $timer.Add_Tick($tickHandler)
    $timer.Start()
}

function Import-CIODIYGuiModules {
    param([Parameter(Mandatory)][string]$AppRoot)

    $modules = @(
        'AppController.ps1','GuiState.ps1','GuiWorkers.ps1','GuiRender.ps1',
        'GuiNavigation.ps1','GuiPages.ps1','GuiEvents.ps1','JobQueue.ps1'
    )
    foreach ($name in $modules) {
        $path = Join-Path $AppRoot (Join-Path 'lib' $name)
        if (-not (Test-Path $path)) {
            throw "Missing GUI module: lib\$name"
        }
        . $path
    }
    if (-not (Get-Command Initialize-CIODIYGuiLogCallback -ErrorAction SilentlyContinue)) {
        throw 'GUI module load failed: Initialize-CIODIYGuiLogCallback'
    }
}
