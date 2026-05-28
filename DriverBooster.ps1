# Driver Booster v1.8.0 - entry point (GUI shell + CLI)
#requires -Version 5.1

param(
    [switch]$ScanOnly,
    [switch]$FixAll,
    [switch]$NoGui,
    [switch]$IncludeOutdated,
    [switch]$RollbackOnError,
    [switch]$Rollback,
    [switch]$RollbackLast,
    [switch]$DeployMode,
    [switch]$AutoFix,
    [switch]$RebootIfNeeded,
    [switch]$NoDeployReport,
    [switch]$DeploySilent,
    [switch]$HealthOnly,
    [string]$TxId = '',
    [ValidateSet('all', 'audio', 'network', 'usb')]
    [string]$Scenario = 'all'
)

# Hide console window immediately to avoid the brief black flash users see when
# Start-Process -Verb RunAs creates an elevated PowerShell host. -WindowStyle
# Hidden alone is unreliable across the UAC trust boundary.
try {
    Add-Type -Namespace Win32 -Name ConsoleHide -MemberDefinition @'
        [System.Runtime.InteropServices.DllImport("kernel32.dll")]
        public static extern System.IntPtr GetConsoleWindow();
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@ -ErrorAction Stop
    $__hwnd = [Win32.ConsoleHide]::GetConsoleWindow()
    if ($__hwnd -ne [System.IntPtr]::Zero) {
        [void][Win32.ConsoleHide]::ShowWindow($__hwnd, 0)
    }
} catch {}

$script:AppRoot = $PSScriptRoot
$script:AppVersion = '2.2.3'
$global:DriverBoosterAppRoot = $script:AppRoot

. (Join-Path $PSScriptRoot 'lib\Utils.ps1')
. (Join-Path $PSScriptRoot 'lib\AppStartup.ps1')

# Write the very first log entry before WPF assemblies load.
# Launch.vbs polls for this file; it must appear within its 15-second window.
Write-CIODIYStartupLog -Message ('Process started v{0} PID={1}' -f $script:AppVersion, $PID) -AppRoot $PSScriptRoot

# --- Splash screen helpers ---------------------------------------------------
$script:SplashWindow = $null
$script:SplashStatusText = $null

function Show-CIODIYSplash {
    if ($NoGui -or $ScanOnly -or $FixAll -or $Rollback -or $RollbackLast -or $HealthOnly -or $DeployMode) {
        return
    }
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        Add-Type -AssemblyName PresentationCore       -ErrorAction Stop
        Add-Type -AssemblyName WindowsBase            -ErrorAction Stop

        $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Width="400" Height="220" WindowStartupLocation="CenterScreen"
        Topmost="True" ResizeMode="NoResize" ShowInTaskbar="False">
  <Border Background="#1A1F2C" CornerRadius="14" BorderBrush="#FF6B00" BorderThickness="2" Margin="14">
    <Border.Effect>
      <DropShadowEffect BlurRadius="22" ShadowDepth="0" Color="Black" Opacity="0.55"/>
    </Border.Effect>
    <StackPanel VerticalAlignment="Center" Margin="0,8,0,18">
      <Border Width="58" Height="58" CornerRadius="12" HorizontalAlignment="Center">
        <Border.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#FF8533" Offset="0"/>
            <GradientStop Color="#FF6B00" Offset="1"/>
          </LinearGradientBrush>
        </Border.Background>
        <TextBlock Text="Y" FontSize="32" FontWeight="Bold" Foreground="White"
                   HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <TextBlock Text="Yanbai驱动" FontSize="20" FontWeight="Bold" Foreground="#F1F5F9"
                 HorizontalAlignment="Center" Margin="0,14,0,2"/>
      <TextBlock Text="砚白 · 智能驱动检测" FontSize="10" Foreground="#FF8533"
                 HorizontalAlignment="Center" Margin="0,0,0,14"/>
      <TextBlock x:Name="TxtSplashStatus" Text="正在启动..." FontSize="11"
                 Foreground="#94A3B8" HorizontalAlignment="Center" Margin="0,0,0,12"/>
      <Border CornerRadius="2" Background="#232936" Width="240" Height="3" HorizontalAlignment="Center">
        <ProgressBar IsIndeterminate="True" Background="Transparent" Foreground="#FF6B00" BorderThickness="0"/>
      </Border>
    </StackPanel>
  </Border>
</Window>
'@
        [xml]$xmlDoc = $xaml
        $reader = New-Object System.Xml.XmlNodeReader $xmlDoc
        $script:SplashWindow = [Windows.Markup.XamlReader]::Load($reader)
        $script:SplashStatusText = $script:SplashWindow.FindName('TxtSplashStatus')
        $script:SplashWindow.Show()
        # Pump until rendered so the splash actually appears before engine load blocks
        $frame = New-Object System.Windows.Threading.DispatcherFrame
        [void]$script:SplashWindow.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::ContextIdle,
            [System.Action]{ $frame.Continue = $false })
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    } catch {
        Write-CIODIYStartupLog -Message ("Splash failed: {0}" -f $_.Exception.Message) -AppRoot $script:AppRoot
    }
}

function Update-CIODIYSplash {
    param([string]$Status)
    if (-not $script:SplashWindow -or -not $script:SplashStatusText) { return }
    try {
        $script:SplashWindow.Dispatcher.Invoke([System.Action]{
            $script:SplashStatusText.Text = $Status
        })
        # Allow paint
        $frame = New-Object System.Windows.Threading.DispatcherFrame
        [void]$script:SplashWindow.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::ContextIdle,
            [System.Action]{ $frame.Continue = $false })
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    } catch {}
}

function Close-CIODIYSplash {
    if (-not $script:SplashWindow) { return }
    try { $script:SplashWindow.Close() } catch {}
    $script:SplashWindow = $null
    $script:SplashStatusText = $null
}

Show-CIODIYSplash

$ErrorActionPreference = 'Stop'

try {
    Update-CIODIYSplash -Status '正在校验程序文件...'
    Initialize-CIODIYEngine -AppRoot $script:AppRoot
    Write-CIODIYStartupLog -Message 'Loading engine' -AppRoot $script:AppRoot
    Update-CIODIYSplash -Status '正在加载驱动引擎...'
    . (Join-Path $script:AppRoot 'engine\DriverEngine.ps1') -AppRoot $script:AppRoot
    Write-CIODIYStartupLog -Message 'Engine loaded' -AppRoot $script:AppRoot
} catch {
    Close-CIODIYSplash
    Show-CIODIYStartupFailure -Message $_.Exception.Message -AppRoot $script:AppRoot -Detail $_.ScriptStackTrace
    exit 1
}

# 直接在脚本作用域 dot-source GUI 模块（不能在函数内 dot-source，否则定义不会传到外层作用域）
foreach ($guiMod in @('AppController.ps1','GuiState.ps1','GuiWorkers.ps1','GuiRender.ps1',
                       'GuiNavigation.ps1','GuiPages.ps1','GuiEvents.ps1',
                       'JobQueue.ps1',
                       'TrayIcon.ps1','RebootDialog.ps1','DriverDetailPanel.ps1')) {
    $guiModPath = Join-Path $script:AppRoot "lib\$guiMod"
    if (-not (Test-Path $guiModPath)) {
        Show-CIODIYStartupFailure -Message "缺少 GUI 模块: lib\$guiMod" -AppRoot $script:AppRoot
        exit 1
    }
    . $guiModPath
}
Write-CIODIYStartupLog -Message 'GUI modules loaded' -AppRoot $script:AppRoot
Update-CIODIYSplash -Status '正在准备界面...'

$null = New-AppSessionState

# NOTE: prior versions ran a background prefetch runspace here to warm up
# WMI/PnP queries during splash. We removed it because:
# 1. It saved < 1s in practice (winmgmt service caching is short-lived).
# 2. It could race with the worker runspace's WMI calls and stall the scan.
# The scan worker runspace alone is fast enough now (~2s) thanks to the batched
# Get-PnpDeviceProperty optimisation in DriverScanner.ps1.
$script:CIODIYPrefetchRunspace = $null
$script:CIODIYPrefetchPS = $null
$script:CIODIYPrefetchAsync = $null

function Show-DriverBoosterGui {
    Write-CIODIYStartupLog -Message 'Show-DriverBoosterGui begin' -AppRoot $script:AppRoot
    Assert-CIODIYStaThread

    if (-not (Test-CIODIYSingleInstance -AppRoot $script:AppRoot)) {
        return
    }

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $xamlPath = Join-Path $PSScriptRoot 'ui\MainWindow.xaml'
    if (-not (Test-Path $xamlPath)) {
        throw "缺少界面文件: ui\MainWindow.xaml"
    }
    [xml]$xaml = Get-Content -Path $xamlPath -Raw -Encoding UTF8
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $iconPath = Join-Path $PSScriptRoot 'ui\yanbai.ico'
    if (Test-Path $iconPath) {
        try {
            $iconUri = [Uri]::new((Resolve-Path $iconPath).Path)
            $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create($iconUri)
        } catch { }
    }

    $uiExceptionHandler = [System.Windows.Threading.DispatcherUnhandledExceptionEventHandler]{
        param($sender, $e)
        $dataRoot = if (Get-Command Get-AppDataRoot -ErrorAction SilentlyContinue) { Get-AppDataRoot } else { $script:AppRoot }
        $logPath = Join-Path $dataRoot 'Logs\startup_error.log'
        try {
            New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'Logs') | Out-Null
            Add-Content -Path $logPath -Value ("[{0}] UI: {1}" -f (Get-Date -Format 'o'), $e.Exception.Message)
        } catch { }
        [System.Windows.MessageBox]::Show($e.Exception.Message, 'Yanbai驱动', 'OK', 'Error') | Out-Null
        $e.Handled = $true
    }
    $window.Dispatcher.add_UnhandledException($uiExceptionHandler)
    $window.Add_Closed({ Remove-CIODIYInstanceLock })

    $controls = Get-CIODIYGuiControlsFromWindow -Window $window
    Test-CIODIYRequiredControls -Controls $controls -Required @(
        'BtnScan', 'BtnFixAll', 'GridDrivers', 'TxtLog', 'Progress', 'TxtProgress', 'TxtSubtitle',
        'PageDashboard', 'BtnNavDashboard'
    )

    . (Join-Path $PSScriptRoot 'lib\GuiDriverRow.ps1')

    $ctx = Initialize-CIODIYGuiContext -Window $window -Controls $controls -AppVersion $script:AppVersion
    Initialize-CIODIYGuiLogCallback
    Register-CIODIYGridLoadingRowHandler
    Register-CIODIYGridSelectionHandler
    Initialize-CIODIYGuiChrome
    Initialize-CIODIYGuiAfterLoad
    Register-CIODIYGuiEvents
    Register-CIODIYGuiNavigation
    Register-CIODIYProblemListHandler

    # Force window to front even from elevated process context (via Loaded event)
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WinFront {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
}
'@ -ErrorAction SilentlyContinue

    $window.Add_Loaded({
        $w = $this
        $w.WindowState = 'Normal'
        $w.Topmost = $true
        $w.Activate()
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($w)).Handle
        if ($hwnd -ne [IntPtr]::Zero) {
            [WinFront]::ShowWindow($hwnd, 9)
            [WinFront]::BringWindowToTop($hwnd)
            [WinFront]::SetForegroundWindow($hwnd)
        }
        $w.Topmost = $false
        Close-CIODIYSplash
    })

    Initialize-CIODIYTrayIcon -Window $window -AppRoot $script:AppRoot

    $window.Add_Closed({
        Stop-CIODIYTrayIcon
        try {
            if ($script:CIODIYPrefetchPS) {
                if ($script:CIODIYPrefetchAsync -and -not $script:CIODIYPrefetchAsync.IsCompleted) {
                    [void]$script:CIODIYPrefetchPS.Stop()
                }
                $script:CIODIYPrefetchPS.Dispose()
            }
            if ($script:CIODIYPrefetchRunspace) { $script:CIODIYPrefetchRunspace.Dispose() }
        } catch {}
    })

    $window.WindowState = 'Normal'
    Write-CIODIYStartupLog -Message "Window shown, entering ShowDialog" -AppRoot $script:AppRoot
    [void]$window.ShowDialog()
}

# --- CLI ---

if ($Rollback -or $RollbackLast) {
    Assert-Admin
    $log = { param($m) Write-Host $m }
    $r = Invoke-DriverRollbackEngine -TxId $TxId -Last:$RollbackLast -OnLog $log
    Write-Host ("Rollback complete: {0} step(s)" -f $r.Count)
    exit 0
}

if ($HealthOnly) {
    Import-AppManifest
    $log = { param($m) Write-Host $m }
    $h = Invoke-DriverHealthEngine -RunScan -FastMatch -OnLog $log
    Write-Host ("HealthScore={0} Label={1}" -f $h.HealthScore, $h.ScoreLabel)
    Write-Host ("Problems={0} Outdated={1} RecommendedFix={2}" -f $h.ProblemCount, $h.OutdatedCount, $h.RecommendedFix)
    foreach ($w in @($h.Warnings)) { Write-Host ("WARN: {0}" -f $w) }
    foreach ($r in @($h.Recommendations)) { Write-Host ("TIP: {0}" -f $r) }
    exit 0
}

if ($DeployMode) {
    Assert-Admin
    Import-AppManifest
    $doAutoFix = if ($PSBoundParameters.ContainsKey('AutoFix')) { [bool]$AutoFix } else { $true }
    $exportReport = -not $NoDeployReport
    $log = if ($DeploySilent) { { param($m) Write-AppLog $m } } else { { param($m) Write-Host $m } }
    $result = Invoke-DeployModeEngine -AutoFix:$doAutoFix -RebootIfNeeded:$RebootIfNeeded `
        -ExportReport:$exportReport -Silent:$DeploySilent -ForceReboot:($RebootIfNeeded -and $NoGui) `
        -FastMatch -Scenario $Scenario -IncludeOutdated:$IncludeOutdated `
        -CreateRestorePoint -BackupFirst -RollbackOnError:$RollbackOnError `
        -AppVersion $script:AppVersion -OnLog $log
    Write-Host ("Deploy status={0} selected={1} report={2}" -f $result.Status, @($result.FixPlanSelected).Count, $result.ReportPath)
    switch ($result.Status) {
        'success' { exit $(if ($result.RebootNeeded) { 2 } else { 0 }) }
        'no_action' { exit 0 }
        'scan_only' { exit 0 }
        'partial' { exit 1 }
        default { exit 1 }
    }
}

if ($NoGui -or $ScanOnly -or $FixAll) {
    Import-AppManifest
    $log = { param($m) Write-Host $m }
    $script:cliPlan = @()
    Invoke-AppScan -OnLog $log -IncludeOutdated:$IncludeOutdated -Scenario $Scenario -OnDone { param($s, $p) $script:cliPlan = $p }
    if ($ScanOnly) {
        foreach ($item in $script:cliPlan) {
            $view = ConvertTo-CIODIYFixPlanItem -InternalItem $item
            Write-Host ("[{0}] {1} -> {2} | {3} tier={4} confidence={5}%" -f `
                $view.StatusText, $view.DisplayName, $view.Source, $view.PackageName, $view.RecommendTier, $view.Confidence)
        }
        exit 0
    }
    if ($FixAll) {
        Assert-Admin
        $r = Invoke-DriverFixEngine -FixPlan $script:cliPlan -CreateRestorePoint -BackupFirst `
            -RollbackOnError:$RollbackOnError -OnLog $log
        $ok = @($r.Results | Where-Object Success).Count
        Write-Host ("Done tx={0} status={1} success={2}" -f $r.TransactionId, $r.FinalStatus, $ok)
        exit $(if ($r.FinalStatus -eq 'committed') { if ($r.RebootNeeded) { 2 } else { 0 } } else { 1 })
    }
}

if (-not (Test-IsAdmin)) {
    # Plain GUI/scan can run without elevation. Only CLI actions that install,
    # deploy, or rollback drivers need to request UAC before continuing.
    $needsElevation = $FixAll -or $DeployMode -or $Rollback -or $RollbackLast
    if (-not $needsElevation) {
        Write-CIODIYStartupLog -Message 'Starting GUI without admin elevation' -AppRoot $script:AppRoot
    } else {
    $exe = $PSCommandPath
    if (-not $exe) {
        try { $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { }
    }
    if ($exe) {
        $argList = @('-NoProfile', '-Sta', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$exe`"")
        if ($ScanOnly)      { $argList += '-ScanOnly' }
        if ($FixAll)        { $argList += '-FixAll' }
        if ($NoGui)         { $argList += '-NoGui' }
        if ($DeployMode)    { $argList += '-DeployMode' }
        if ($AutoFix)       { $argList += '-AutoFix' }
        if ($RebootIfNeeded){ $argList += '-RebootIfNeeded' }
        if ($NoDeployReport){ $argList += '-NoDeployReport' }
        if ($DeploySilent)  { $argList += '-DeploySilent' }
        if ($RollbackOnError){ $argList += '-RollbackOnError' }
        if ($IncludeOutdated){ $argList += '-IncludeOutdated' }
        if ($Scenario -and $Scenario -ne 'all') { $argList += '-Scenario'; $argList += $Scenario }
        if ($Rollback)      { $argList += '-Rollback' }
        if ($RollbackLast)  { $argList += '-RollbackLast' }
        Write-CIODIYStartupLog -Message 'Requesting admin elevation (RunAs)' -AppRoot $script:AppRoot
        Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList $argList
        exit 0
    }
    }
}

try {
    Show-DriverBoosterGui
} catch {
    Show-CIODIYStartupFailure -Message $_.Exception.Message -AppRoot $script:AppRoot -Detail $_.ScriptStackTrace
    exit 1
} finally {
    Remove-CIODIYInstanceLock
}
