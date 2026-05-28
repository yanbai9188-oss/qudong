# Driver detail sliding drawer (v1.8.9)

$script:CIODIYDriverDetailHwid = $null

function Show-CIODIYDriverDetailDrawer {
    param([Parameter(Mandatory)]$GridRow)

    $ctx = Get-CIODIYGuiContext
    $drawer = Get-CIODIYGuiControl -Name 'DriverDetailDrawer'
    if (-not $drawer) { return }

    $key = [string]$GridRow.DeviceKey
    if (-not $ctx.State.FixPlanByKey.ContainsKey($key)) { return }
    $item = $ctx.State.FixPlanByKey[$key]
    $details = Get-DriverFixItemDetails -Item $item
    $dev = $item.Device
    $pkg = $item.Package

    # Header device name
    $txtDev = Get-CIODIYGuiControl -Name 'TxtDrawerDeviceName'
    if ($txtDev) { $txtDev.Text = $details.DeviceName }

    $curVer = if ($details.CurrentVersion) { $details.CurrentVersion } else { '未安装' }
    $tgtVer = if ($details.TargetVersion) { $details.TargetVersion } else { '-' }

    $txtCur = Get-CIODIYGuiControl -Name 'TxtDrawerCurrentVer'
    if ($txtCur) { $txtCur.Text = $curVer }
    $txtTgt = Get-CIODIYGuiControl -Name 'TxtDrawerTargetVer'
    if ($txtTgt) { $txtTgt.Text = $tgtVer }

    # Badges
    $badgePanel = Get-CIODIYGuiControl -Name 'DrawerBadges'
    if ($badgePanel) {
        $badgePanel.Children.Clear()
        $badges = @()
        if ($details.VersionStatusLabel) {
            $badges += @{ Text = $details.VersionStatusLabel; Color = '#FF6B00' }
        }
        if ($details.RecommendTier) {
            $color = switch ($details.RecommendTier) {
                'Recommended' { '#22C55E' }
                'Optional'    { '#3B82F6' }
                'Unsafe'      { '#EF4444' }
                default       { '#94A3B8' }
            }
            $badges += @{ Text = "推荐: $($details.RecommendTier)"; Color = $color }
        }
        if ($details.Whql) { $badges += @{ Text = 'WHQL 签名'; Color = '#22C55E' } }
        if ($details.RebootRequired) { $badges += @{ Text = '需重启'; Color = '#F59E0B' } }
        if ($details.RiskLevel) {
            $rcolor = switch ($details.RiskLevel) {
                'low'    { '#22C55E' }
                'medium' { '#F59E0B' }
                'high'   { '#EF4444' }
                default  { '#94A3B8' }
            }
            $rtext = switch ($details.RiskLevel) {
                'low'    { '低风险' }
                'medium' { '中等风险' }
                'high'   { '高风险' }
                default  { $details.RiskLevel }
            }
            $badges += @{ Text = $rtext; Color = $rcolor }
        }
        foreach ($b in $badges) {
            $brd = New-Object System.Windows.Controls.Border
            $brd.Background = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString('#232936'))
            $brd.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($b.Color))
            $brd.BorderThickness = New-Object System.Windows.Thickness 1
            $brd.CornerRadius = New-Object System.Windows.CornerRadius 4
            $brd.Padding = New-Object System.Windows.Thickness 8, 3, 8, 3
            $brd.Margin = New-Object System.Windows.Thickness 0, 0, 6, 6
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $b.Text
            $tb.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($b.Color))
            $tb.FontSize = 10
            $tb.FontWeight = 'SemiBold'
            $brd.Child = $tb
            [void]$badgePanel.Children.Add($brd)
        }
    }

    # Detail rows
    $listPanel = Get-CIODIYGuiControl -Name 'DrawerDetailList'
    if ($listPanel) {
        $listPanel.Children.Clear()

        $hwids = @()
        if ($dev) {
            if ($dev.HardwareIDs) { $hwids += @($dev.HardwareIDs) }
            elseif ($dev.HardwareID) { $hwids += @($dev.HardwareID) }
        }
        $hwids = @($hwids | Where-Object { $_ } | Select-Object -Unique)
        $script:CIODIYDriverDetailHwid = ($hwids -join "`r`n")

        $rows = @(
            @{ Label = '设备类别'; Value = (if ($pkg) { [string]$pkg.Category } else { '-' }) }
            @{ Label = '驱动来源'; Value = $details.SourceLabel }
            @{ Label = '匹配原因'; Value = $details.MatchReason }
            @{ Label = '可信度'; Value = $details.TrustBadge }
            @{ Label = '匹配置信度'; Value = ('{0}%' -f $details.Confidence) }
        )
        if ($details.PackageSize) {
            $rows += @{ Label = '驱动包大小'; Value = $details.PackageSize }
        }
        if ($pkg -and $pkg.Vendor) {
            $rows += @{ Label = '厂商'; Value = [string]$pkg.Vendor }
        }
        if ($pkg -and $pkg.url) {
            $rows += @{ Label = '下载地址'; Value = [string]$pkg.url; IsUrl = $true }
        }
        if ($pkg -and $pkg.sha256) {
            $rows += @{ Label = 'SHA256'; Value = [string]$pkg.sha256; IsMono = $true }
        }
        if ($hwids.Count -gt 0) {
            $rows += @{ Label = "硬件 ID ($($hwids.Count) 个)"; Value = ($hwids -join "`n"); IsMono = $true }
        }
        if ($details.RiskReasons -and @($details.RiskReasons).Count -gt 0) {
            $rows += @{ Label = '风险说明'; Value = (@($details.RiskReasons) -join '；'); Color = '#F59E0B' }
        }

        foreach ($r in $rows) {
            $rowPanel = New-Object System.Windows.Controls.StackPanel
            $rowPanel.Margin = New-Object System.Windows.Thickness 0, 0, 0, 10

            $labelTb = New-Object System.Windows.Controls.TextBlock
            $labelTb.Text = $r.Label
            $labelTb.FontSize = 10
            $labelTb.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString('#64748B'))
            $labelTb.Margin = New-Object System.Windows.Thickness 0, 0, 0, 2
            [void]$rowPanel.Children.Add($labelTb)

            $valueTb = New-Object System.Windows.Controls.TextBlock
            $valueTb.Text = [string]$r.Value
            $valueTb.FontSize = 11
            $valueTb.TextWrapping = 'Wrap'
            $color = if ($r.Color) { $r.Color } else { '#CBD5E1' }
            $valueTb.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($color))
            if ($r.IsMono) {
                $valueTb.FontFamily = New-Object System.Windows.Media.FontFamily 'Consolas, Cascadia Mono, Courier New'
                $valueTb.FontSize = 10
            }
            [void]$rowPanel.Children.Add($valueTb)

            [void]$listPanel.Children.Add($rowPanel)
        }
    }

    # Slide in animation
    $drawer.Visibility = 'Visible'
    $transform = $drawer.RenderTransform
    if ($transform) {
        $anim = New-Object System.Windows.Media.Animation.DoubleAnimation 0, ([TimeSpan]::FromMilliseconds(280))
        $anim.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase
        $anim.EasingFunction.EasingMode = 'EaseOut'
        $transform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $anim)
    }
}

function Hide-CIODIYDriverDetailDrawer {
    $drawer = Get-CIODIYGuiControl -Name 'DriverDetailDrawer'
    if (-not $drawer) { return }
    $transform = $drawer.RenderTransform
    if (-not $transform) {
        $drawer.Visibility = 'Collapsed'
        return
    }
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation 400, ([TimeSpan]::FromMilliseconds(220))
    $anim.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase
    $anim.EasingFunction.EasingMode = 'EaseIn'
    $anim.add_Completed({
        try {
            $d = Get-CIODIYGuiControl -Name 'DriverDetailDrawer'
            if ($d) { $d.Visibility = 'Collapsed' }
        } catch {}
    }.GetNewClosure())
    $transform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $anim)
}

function Register-CIODIYDriverDetailDrawer {
    $btnClose = Get-CIODIYGuiControl -Name 'BtnDrawerClose'
    if ($btnClose) {
        $btnClose.Add_Click({ Hide-CIODIYDriverDetailDrawer }.GetNewClosure())
    }

    $btnCopy = Get-CIODIYGuiControl -Name 'BtnDrawerCopyHwid'
    if ($btnCopy) {
        $btnCopy.Add_Click({
            if ($script:CIODIYDriverDetailHwid) {
                try {
                    [System.Windows.Clipboard]::SetText($script:CIODIYDriverDetailHwid)
                    Show-CIODIYToast -Message 'HWID 已复制到剪贴板' -Level Success -DurationMs 2500
                } catch {
                    Show-CIODIYToast -Message ('复制失败：{0}' -f $_.Exception.Message) -Level Error
                }
            } else {
                Show-CIODIYToast -Message '当前驱动无 HWID 信息' -Level Warning
            }
        }.GetNewClosure())
    }
}
