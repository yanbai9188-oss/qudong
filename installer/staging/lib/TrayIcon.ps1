# System tray icon + close-to-tray (v1.8.9)

$script:CIODIYTrayIcon = $null
$script:CIODIYTrayMenu = $null
$script:CIODIYExitRequested = $false
$script:CIODIYTrayHintShown = $false

function Initialize-CIODIYTrayIcon {
    param(
        [Parameter(Mandatory)] $Window,
        [Parameter(Mandatory)] [string]$AppRoot
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing       -ErrorAction Stop
    } catch {
        Write-CIODIYStartupLog -Message ("Tray init: WinForms unavailable: {0}" -f $_.Exception.Message) -AppRoot $AppRoot
        return
    }

    $iconPath = Join-Path $AppRoot 'ui\yanbai.ico'
    $tray = New-Object System.Windows.Forms.NotifyIcon
    if (Test-Path $iconPath) {
        try { $tray.Icon = New-Object System.Drawing.Icon $iconPath } catch {
            $tray.Icon = [System.Drawing.SystemIcons]::Application
        }
    } else {
        $tray.Icon = [System.Drawing.SystemIcons]::Application
    }
    $tray.Text = 'Yanbai驱动 - 智能驱动检测'
    $tray.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    $itemShow = New-Object System.Windows.Forms.ToolStripMenuItem '打开主窗口'
    $itemShow.Font = New-Object System.Drawing.Font($itemShow.Font, [System.Drawing.FontStyle]::Bold)
    $itemShow.add_Click({ Show-CIODIYTrayWindow -Window $Window }.GetNewClosure())
    [void]$menu.Items.Add($itemShow)

    $itemScan = New-Object System.Windows.Forms.ToolStripMenuItem '立即扫描驱动'
    $itemScan.add_Click({
        Show-CIODIYTrayWindow -Window $Window
        try {
            $Window.Dispatcher.BeginInvoke([System.Action]{
                $btn = Get-CIODIYGuiControl -Name 'BtnScan'
                if ($btn -and $btn.IsEnabled) {
                    $btn.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                }
            }) | Out-Null
        } catch {}
    }.GetNewClosure())
    [void]$menu.Items.Add($itemScan)

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $itemAbout = New-Object System.Windows.Forms.ToolStripMenuItem '关于 Yanbai驱动'
    $itemAbout.add_Click({
        $msg = "Yanbai驱动 v$($script:AppVersion)" + [Environment]::NewLine +
               "智能驱动检测与一键修复" + [Environment]::NewLine + [Environment]::NewLine +
               "在线模式 · 节省安装包体积" + [Environment]::NewLine +
               "Win10 / Win11 一体机优化"
        [System.Windows.Forms.MessageBox]::Show($msg, '关于 Yanbai驱动',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }.GetNewClosure())
    [void]$menu.Items.Add($itemAbout)

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $itemExit = New-Object System.Windows.Forms.ToolStripMenuItem '退出 Yanbai驱动'
    $itemExit.add_Click({
        $script:CIODIYExitRequested = $true
        try { $script:CIODIYTrayIcon.Visible = $false } catch {}
        try { $script:CIODIYTrayIcon.Dispose() } catch {}
        $Window.Dispatcher.BeginInvoke([System.Action]{ $Window.Close() }) | Out-Null
    }.GetNewClosure())
    [void]$menu.Items.Add($itemExit)

    $tray.ContextMenuStrip = $menu

    $tray.add_MouseDoubleClick({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            Show-CIODIYTrayWindow -Window $Window
        }
    }.GetNewClosure())

    $script:CIODIYTrayIcon = $tray
    $script:CIODIYTrayMenu = $menu

    # Intercept window Close (X button or Alt+F4) -> minimize to tray
    $Window.Add_Closing({
        param($sender, $e)
        if ($script:CIODIYExitRequested) { return }
        $e.Cancel = $true
        $Window.Hide()
        if (-not $script:CIODIYTrayHintShown -and $script:CIODIYTrayIcon) {
            try {
                $script:CIODIYTrayIcon.BalloonTipTitle = 'Yanbai驱动'
                $script:CIODIYTrayIcon.BalloonTipText  = '已最小化到系统托盘，双击图标可重新打开'
                $script:CIODIYTrayIcon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
                $script:CIODIYTrayIcon.ShowBalloonTip(3000)
            } catch {}
            $script:CIODIYTrayHintShown = $true
        }
    }.GetNewClosure())

    Write-CIODIYStartupLog -Message 'Tray icon initialized' -AppRoot $AppRoot
}

function Show-CIODIYTrayWindow {
    param($Window)
    if (-not $Window) { return }
    try {
        $Window.Dispatcher.Invoke([System.Action]{
            if (-not $Window.IsVisible) { $Window.Show() }
            if ($Window.WindowState -eq 'Minimized') { $Window.WindowState = 'Normal' }
            $Window.Topmost = $true
            $Window.Activate()
            $Window.Topmost = $false
            $Window.Focus() | Out-Null
        })
    } catch {}
}

function Stop-CIODIYTrayIcon {
    if ($script:CIODIYTrayIcon) {
        try { $script:CIODIYTrayIcon.Visible = $false } catch {}
        try { $script:CIODIYTrayIcon.Dispose() } catch {}
        $script:CIODIYTrayIcon = $null
    }
    if ($script:CIODIYTrayMenu) {
        try { $script:CIODIYTrayMenu.Dispose() } catch {}
        $script:CIODIYTrayMenu = $null
    }
}
